#!/usr/bin/env node
/**
 * layout.mjs — 平面设计工坊的「规格 → 版式」编译器
 *
 * 模型只写一份声明式 design.json（页面、网格、色板、块），
 * 由本工具做确定性排版：量文字 → 算几何 → 生成 DesignCraft 文档 → 导出。
 *
 * 用法：
 *   node layout.mjs lint  design.json                 纯静态检查，不启动引擎
 *   node layout.mjs plan  design.json [--dcs out.dcs] 打印/导出命令行（估算高度，不启动引擎）
 *   node layout.mjs run   design.json --out dir       量文字 + 排版 + 导出 PNG/PDF
 *
 * 常用选项：
 *   --slug <name>     输出文件名（默认 design）
 *   --scale <n>       PNG 像素/点（默认 2）
 *   --no-png / --no-pdf
 *   --fit            自动缩字号让溢出文字装进框（最多 4 轮，引擎实测）
 *   --strict         有任何 warn 也返回非 0
 *   --json           只输出 JSON（默认就是）
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { normalize, resolveBox, leadingPt, walk } from "./lib/spec.mjs";
import { lint } from "./lib/lint.mjs";
import { DesignCraft } from "./lib/mcp.mjs";

// ---------------------------------------------------------------- cli

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) out[key] = true;
    else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0] || "run";
const specPath = args._[1] ? path.resolve(args._[1]) : null;
if (!specPath) {
  console.error("用法: node layout.mjs <lint|plan|run> <design.json> [--out dir] [--slug name]");
  process.exit(1);
}

const spec = JSON.parse(readFileSync(specPath, "utf8").replace(/^\uFEFF/, ""));
const baseDir = path.dirname(specPath);
const model = normalize(spec);
// 先算一遍几何（高度用估算），拿到每个块的最终宽度 —— 量文字要用它。
const preGeo = computeGeometry(model);
const lintResult = lint({ ctx: model.ctx, spec, leaves: preGeo.leaves, errors: model.errors }, { baseDir });
const baseIssues = [...lintResult.issues];

// ---------------------------------------------------------------- 几何

const round2 = (n) => Math.round(n * 100) / 100;

/** 用估算高度做无引擎排版（plan 用）；中日韩按 1em、西文按 0.55em，含字距 */
function estimateHeight(b) {
  const lh = leadingPt(b.size, b.leading);
  const width = b.box.w || 1;
  const charW = b.size * (1 + (b.tracking || 0) / 1000);
  let lines = 0;
  for (const para of String(b.text).split("\n")) {
    const units = [...para].reduce((s, ch) => s + (/[\u3000-\u9fff\uff00-\uffef]/.test(ch) ? 1 : 0.55), 0);
    lines += Math.max(1, Math.ceil((units * charW) / width));
  }
  return lines * lh;
}

/**
 * 把块树摊平成「带最终盒子」的叶子序列。heights: id → 实测高度。
 * 返回 { leaves, issues }
 */
function computeGeometry(model, heights = {}) {
  const issues = [];
  const leaves = [];
  const page = model.ctx.page;

  const heightOf = (b) => {
    if (b.kind !== "text") return b.box.h ?? 0;
    if (b.fixedH != null) return b.fixedH;
    const measured = heights[b.id];
    return measured != null ? measured : estimateHeight(b);
  };

  const place = (b, parent = null) => {
    // 宽度先定：子块继承容器
    if (b.box.x == null) {
      if (parent) b.box.x = parent.box.x;
      else issues.push({ level: "error", code: "box.noX", where: b.where, msg: "块没有 x/col，也不在容器里", fix: "给 col 或 x" });
    }
    if (b.box.w == null) {
      if (parent) b.box.w = parent.box.w;
      else issues.push({ level: "error", code: "box.noW", where: b.where, msg: "块没有宽（w/span）", fix: "给 span 或 w" });
    }
    if (b.box.w == null || b.box.w <= 0) b.box.w = page.content.w;

    if (b.kind === "stack") {
      let y = b.box.y ?? 0;
      if (b.box.y == null) {
        if (parent) b.box.y = parent.box.y;
        else issues.push({ level: "error", code: "box.noY", where: b.where, msg: "stack 没有 y", fix: "给 y 或把它放进别的容器" });
        y = b.box.y ?? page.content.y;
      }
      const gap = b.gap ?? 12;
      let first = true;
      for (const c of b.children) {
        if (!first) y += gap;
        first = false;
        c.box.x = c.box.x ?? b.box.x;
        c.box.w = c.box.w ?? b.box.w;
        c.box.y = y;
        place(c, b);
        y += c.box.h ?? 0;
      }
      b.box.h = first ? 0 : y - (b.box.y ?? 0);
      return;
    }

    if (b.kind === "row") {
      const gap = b.gap ?? 12;
      const n = b.children.length;
      const total = b.box.w - gap * (n - 1);
      const weights = b.widths || b.children.map((c) => c.raw?.weight ?? 1);
      const sum = weights.reduce((a, c) => a + c, 0) || 1;
      let x = b.box.x;
      b.children.forEach((c, i) => {
        const cw = (total * weights[i]) / sum;
        c.box.x = x;
        c.box.w = cw;
        c.box.y = b.box.y;
        place(c, b);
        x += cw + gap;
      });
      // 行高 = 子块最高者；父容器靠它推进（v4.1 修复：以前是 0，后面的块会叠上来）
      if (b.box.h == null) b.box.h = b.children.reduce((m, c) => Math.max(m, c.box.h ?? 0), 0);
      return;
    }

    // 叶子
    if (b.box.y == null) {
      issues.push({ level: "error", code: "box.noY", where: b.where, msg: "块没有 y，也不在 stack/row 里", fix: "给 y，或把它放进 stack" });
      b.box.y = page.content.y;
    }
    b.box.h = heightOf(b);
    b.measuredH = heights[b.id] ?? null;
    leaves.push(b);
  };

  for (const b of model.blocks) place(b);
  return { leaves, issues };
}

// ---------------------------------------------------------------- 排版会话

const swatchOf = (color, ctx) => {
  if (!color || color.kind === "none") return null;
  if (color.kind === "token") {
    const n = color.name.charAt(0).toUpperCase() + color.name.slice(1);
    return n;
  }
  if (color.kind === "cmyk") {
    const c = color.cmyk;
    return `C${Math.round(c.c)}M${Math.round(c.m)}Y${Math.round(c.y)}K${Math.round(c.k)}`;
  }
  if (color.kind === "hex") return color.hex.replace("#", "").toUpperCase();
  return null;
};

async function colorParams(color, ctx) {
  if (color.kind === "token") return ctx.mode === "print" && color.cmyk ? { c: color.cmyk.c, m: color.cmyk.m, y: color.cmyk.y, k: color.cmyk.k } : color.hex;
  if (color.kind === "cmyk") return color.cmyk;
  if (color.kind === "hex") return ctx.mode === "print" && color.cmyk ? color.cmyk : color.hex;
  return null;
}

function collectColors(model) {
  const map = new Map(); // swatchName → color
  walk(model.blocks, (b) => {
    for (const c of [b.fill, b.color, b.stroke?.color]) {
      if (!c || c.kind === "none") continue;
      const n = swatchOf(c, model.ctx);
      if (n && !map.has(n)) map.set(n, c);
    }
    // stack/row 没有颜色
  });
  return map;
}

async function createSwatches(dc, model) {
  const colors = collectColors(model);
  const cmds = [];
  for (const [name, color] of colors) {
    const p = await colorParams(color, model.ctx);
    if (p) cmds.push({ command: "swatch.create", params: { name, color: p } });
  }
  // 色板里的 token 即使没用到也建出来？不建，省步骤。
  return dc.batch(cmds);
}

function textCharAttrs(b) {
  const attrs = {
    fontFamily: b.font,
    size: b.size,
    leading: { kind: "points", value: round2(leadingPt(b.size, b.leading)) },
  };
  if (b.tracking) attrs.tracking = b.tracking;
  if (b.fontStyle) attrs.fontStyle = b.fontStyle;
  return attrs;
}

/** 第一遍：在临时文档里量每个文字块的真实高度 */
async function measureText(dc, model, leaves) {
  const page = model.ctx.page;
  const doc = await dc.json("new_document", {
    width: page.w,
    height: page.h,
    margins: { top: page.margins.top, bottom: page.margins.bottom, inside: page.margins.left, outside: page.margins.right },
    bleed: page.maxBleed,
    intent: model.ctx.intent,
    facingPages: false,
    pages: 1,
    title: "measure",
  });
  void doc;

  const textLeaves = leaves.filter((b) => b.kind === "text");

  const ids = [];
  for (const b of textLeaves) {
    const res = await dc.batch([
      { command: "frame.create", params: { rect: [0, 0, round2(b.box.w), 10], content: "text", text: b.text } },
    ]);
    const id = res.results?.[0]?.id;
    if (!id) throw new Error(`量文字失败：${b.id}`);
    ids.push({ b, id });
    const cmds = [
      { command: "text.selectStory", params: { frame: id, point: [1, 1] } },
      { command: "type.char", params: { attrs: textCharAttrs(b) } },
      { command: "object.textFrameOptions", params: { autoSize: "heightOnly", autoSizeReference: "topLeft", ids: [id] } },
    ];
    if (b.align && b.align !== "left") cmds.push({ command: "type.para", params: { attrs: { align: b.align } } });
    await dc.batch(cmds);
  }

  const heights = {};
  const lines = {};
  const overset = {};
  const inspect = await dc.json("inspect_document", {});
  const items = inspect.spreads?.[0]?.items || [];
  const byId = new Map(items.map((it) => [it.id, it]));
  for (const { b, id } of ids) {
    const it = byId.get(id);
    if (!it) throw new Error(`量文字失败：找不到 frame ${id} (${b.id})`);
    heights[b.id] = round2(it.bounds[3] - it.bounds[1]);
    const st = (inspect.stories || []).find((s) => s.frames?.includes(id));
    lines[b.id] = st?.lines ?? null;
    overset[b.id] = !!st?.overset;
  }
  return { heights, lines, overset, docIndex: inspect.spreadIndex };
}

/** 第二遍：正式文档，按 spec 顺序建（决定叠放顺序） */
async function buildDocument(dc, model, geo) {
  const page = model.ctx.page;
  await dc.json("new_document", {
    width: page.w,
    height: page.h,
    margins: { top: page.margins.top, bottom: page.margins.bottom, inside: page.margins.left, outside: page.margins.right },
    bleed: page.maxBleed,
    intent: model.ctx.intent,
    facingPages: false,
    pages: 1,
    title: model.spec.title || "design",
  });
  await createSwatches(dc, model);

  const ids = {};
  const failed = [];
  for (const b of geo.leaves) {
    try {
      if (b.kind === "text") {
        const rect = [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + (b.box.h || 10))];
        const r = await dc.batch([{ command: "frame.create", params: { rect, content: "text", text: b.text } }]);
        const id = r.results?.[0]?.id;
        ids[b.id] = id;
        const chars = textCharAttrs(b);
        const sw = swatchOf(b.color, model.ctx);
        if (sw) chars.fill = sw;
        const cmds = [
          { command: "text.selectStory", params: { frame: id, point: [round2(b.box.x + 1), round2(b.box.y + 1)] } },
          { command: "type.char", params: { attrs: chars } },
        ];
        if (b.valign && b.valign !== "top") {
          cmds.push({ command: "object.textFrameOptions", params: { verticalJustification: b.valign, ids: [id] } });
        }
        if (b.align && b.align !== "left") cmds.push({ command: "type.para", params: { attrs: { align: b.align } } });
        if (b.opacity < 1) cmds.push({ command: "object.opacity", params: { opacity: b.opacity, ids: [id] } });
        await dc.batch(cmds);
      } else if (b.kind === "rect" || b.kind === "line") {
        const rect = [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + b.box.h)];
        const r = await dc.batch([{ command: "frame.create", params: { rect, content: "graphic" } }]);
        const id = r.results?.[0]?.id;
        ids[b.id] = id;
        const cmds = [];
        const f = swatchOf(b.fill, model.ctx);
        if (f) cmds.push({ command: "object.fill", params: { swatch: f, ids: [id] } });
        if (b.stroke) {
          const s = swatchOf(b.stroke.color, model.ctx);
          cmds.push({ command: "object.stroke", params: { swatch: s, weight: b.stroke.weight, align: "inside", ids: [id] } });
        }
        if (b.radius > 0) cmds.push({ command: "object.cornerOptions", params: { shape: "rounded", size: b.radius, ids: [id] } });
        if (b.opacity < 1) cmds.push({ command: "object.opacity", params: { opacity: b.opacity, ids: [id] } });
        if (cmds.length) await dc.batch(cmds);
      } else if (b.kind === "image") {
        const rect = [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + b.box.h)];
        const r = await dc.batch([{ command: "frame.create", params: { rect, content: "graphic" } }]);
        const id = r.results?.[0]?.id;
        ids[b.id] = id;
        const src = /^([A-Za-z]:|\\\\|\/)/.test(b.src) ? b.src : path.resolve(baseDir, b.src);
        await dc.batch([
          { command: "file.place", params: { path: src, frame: id } },
          { command: "object.fit", params: { mode: b.fit === "stretch" ? "fitContentToFrame" : "fillProportionally", ids: [id] } },
        ]);
        if (b.opacity < 1) await dc.batch([{ command: "object.opacity", params: { opacity: b.opacity, ids: [id] } }]);
      }
    } catch (e) {
      failed.push({ id: b.id, where: b.where, error: e.message });
    }
  }
  return { ids, failed };
}

// ---------------------------------------------------------------- 主流程

const report = {
  ok: true,
  spec: specPath,
  page: `${model.ctx.page.w}×${model.ctx.page.h}pt`,
  mode: model.ctx.mode,
  issues: [],
  stats: lintResult.stats,
  out: {},
};

const printAndExit = (code) => {
  console.log(JSON.stringify(report, null, 2));
  process.exit(code);
};

if (cmd === "lint") {
  report.issues = lintResult.issues;
  report.ok = report.issues.every((i) => i.level !== "error") && !(args.strict && report.issues.some((i) => i.level === "warn"));
  printAndExit(report.ok ? 0 : 2);
}

if (cmd === "plan") {
  const geo = computeGeometry(model);
  report.issues = [...lintResult.issues, ...geo.issues];
  report.geometry = geo.leaves.map((b) => ({
    id: b.id,
    kind: b.kind,
    box: [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + (b.box.h || 0))],
    estH: b.kind === "text" ? round2(estimateHeight(b)) : null,
  }));
  report.ok = report.issues.every((i) => i.level !== "error");
  if (args.dcs) {
    const lines = [];
    let i = 0;
    for (const b of geo.leaves) {
      if (b.kind === "text") {
        lines.push(`frame.create ${JSON.stringify({ rect: [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + b.box.h)], content: "text", text: b.text })}`);
        lines.push(`text.selectStory ${JSON.stringify({ frame: `$${i}.id`, point: [round2(b.box.x + 1), round2(b.box.y + 1)] })}`);
        i++;
      } else if (b.kind === "rect" || b.kind === "line") {
        lines.push(`frame.create ${JSON.stringify({ rect: [round2(b.box.x), round2(b.box.y), round2(b.box.x + b.box.w), round2(b.box.y + b.box.h)], content: "graphic" })}`);
        i++;
      }
    }
    writeFileSync(path.resolve(args.dcs), lines.join("\n") + "\n", "utf8");
    report.out.dcs = path.resolve(args.dcs);
  }
  printAndExit(report.ok ? 0 : 2);
}

if (cmd === "run") {
  const outDir = path.resolve(args.out || path.join(baseDir, "out"));
  mkdirSync(outDir, { recursive: true });
  const slug = args.slug || spec.slug || spec.title || "design";
  const dcPath = path.join(outDir, `${slug}.designcraft`);
  const pngPath = path.join(outDir, `${slug}.png`);
  const pdfPath = path.join(outDir, `${slug}.pdf`);

  const dc = new DesignCraft({ cli: args.cli });
  const t0 = Date.now();
  const issues = [];
  try {
    await dc.init();

    // 1) 量文字（独立文档，真字体度量）
    let measured = await measureText(dc, model, preGeo.leaves);

    // 2) 自动缩字（可选）：拿引擎实测的溢出比例逐轮收；到可读下限就停
    if (args.fit) {
      let rounds = 0;
      let hitFloor = false;
      const FLOOR = 5; // pt，低于这个字号不再自动缩
      for (;;) {
        const g = computeGeometry(model, measured.heights);
        const bad = g.leaves.filter((b) => b.kind === "text" && b.fixedH != null && (measured.heights[b.id] ?? 0) > b.fixedH + 0.5);
        if (!bad.length || rounds >= 4) break;
        rounds++;
        for (const b of bad) {
          const ratio = Math.max(0.7, Math.min(0.97, b.fixedH / measured.heights[b.id]));
          const target = Math.max(FLOOR, b.size * ratio);
          if (target <= FLOOR + 0.01) hitFloor = true;
          if (target >= b.size - 0.01) continue;
          b.size = round2(target);
          b.leading = typeof b.leading === "object" ? { pt: round2(leadingPt(b.size, b.leading)) } : b.leading;
        }
        measured = await measureText(dc, model, preGeo.leaves);
        report.fitRounds = rounds;
      }
      if (hitFloor) {
        report.fitFailed = true;
        issues.push({
          level: "error",
          code: "fit.floor",
          where: "fit",
          msg: `自动缩字已到可读下限 ${FLOOR}pt 仍装不下`,
          fix: "加高固定框、删减文字，或接受 `--force` 出片后手工处理",
        });
      }
    }

    // 3) 几何
    const geo = computeGeometry(model, measured.heights);

    // 4) 溢出报告（引擎实测，带可直接执行的修法）
    for (const b of geo.leaves) {
      if (b.kind !== "text") continue;
      const h = measured.heights[b.id];
      if (h == null || b.fixedH == null) continue;
      if (h > b.fixedH + 0.5) {
        const atFloor = b.size <= 6;
        issues.push({
          level: "error",
          code: "text.overflow",
          where: b.where,
          msg: `实测 ${h.toFixed(1)}pt（${measured.lines[b.id] ?? "?"} 行），框高 ${b.fixedH}pt，溢出 ${(h - b.fixedH).toFixed(1)}pt`,
          fix: atFloor
            ? `框加高到 ${Math.ceil(h)}pt（字号已在可读下限，别再缩）`
            : `框加高到 ${Math.ceil(h)}pt，或字号 ×${((b.fixedH / h) * 0.98).toFixed(2)}（当前 ${b.size}pt）`,
        });
      }
    }

    // 用引擎实测高度再跑一遍静态检查（此时越界/溢出判断就是最终真相）
    const finalLint = lint({ ctx: model.ctx, spec, leaves: geo.leaves, errors: model.errors }, { baseDir });
    const allIssues = () => [...finalLint.issues, ...geo.issues, ...issues];
    report.stats = finalLint.stats;

    // 5) 出片闸门：任何 error（含 lint 阶段、模型展开、实测溢出）都拦住 build/export
    const hasError = () => allIssues().some((i) => i.level === "error");
    if (hasError() && !args.force) {
      report.issues = allIssues();
      report.stats.errors = report.issues.filter((i) => i.level === "error").length;
      report.stats.warns = report.issues.filter((i) => i.level === "warn").length;
      report.ok = false;
      report.skippedExport = true;
      report.elapsedMs = Date.now() - t0;
      dc.close();
      printAndExit(2);
    }

    const build = await buildDocument(dc, model, geo);
    for (const f of build.failed) issues.push({ level: "error", code: "build.failed", where: f.where, msg: f.error });

    if (build.failed.length && !args.force) {
      report.issues = allIssues();
      report.stats.errors = report.issues.filter((i) => i.level === "error").length;
      report.stats.warns = report.issues.filter((i) => i.level === "warn").length;
      report.ok = false;
      report.skippedExport = true;
      report.elapsedMs = Date.now() - t0;
      dc.close();
      printAndExit(2);
    }

    await dc.json("save_document", { path: dcPath });
    report.out.designcraft = dcPath;

    if (!args["no-png"]) {
      const png = args["png-bleed"]
        ? await dc.json("render_page", { path: pngPath, page: 0, scale: Number(args.scale || 2), bleed: true })
        : await dc.json("export_png", { path: pngPath, page: 0, scale: Number(args.scale || 2) });
      report.out.png = pngPath;
      if (png?.width) report.out.px = `${png.width}×${png.height}`;
    }
    if (!args["no-pdf"] && model.ctx.intent === "print") {
      try {
        const pdf = await dc.json("execute", {
          command: "file.exportPdf",
          params: { path: pdfPath, standard: "x4", bleed: true, marks: false },
        });
        report.out.pdf = pdf?.path || pdfPath;
      } catch (e) {
        issues.push({ level: "warn", code: "pdf.failed", where: "export", msg: e.message });
      }
    }

    report.issues = allIssues();
    report.stats.errors = report.issues.filter((i) => i.level === "error").length;
    report.stats.warns = report.issues.filter((i) => i.level === "warn").length;
    report.ok = !report.stats.errors && !(args.strict && report.stats.warns);
    report.stats.blocks = geo.leaves.length;
    report.elapsedMs = Date.now() - t0;
  } catch (e) {
    report.ok = false;
    report.issues = [...baseIssues, ...issues, { level: "error", code: "crash", where: "run", msg: e.message }];
    report.elapsedMs = Date.now() - t0;
  } finally {
    dc.close();
  }
  printAndExit(report.ok ? 0 : 2);
}

console.error(`未知子命令 ${cmd}（lint|plan|run）`);
process.exit(1);
