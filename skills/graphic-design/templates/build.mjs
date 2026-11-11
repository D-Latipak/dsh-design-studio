#!/usr/bin/env node
// 设计模板构建器：把模板 + 槽位值 → DesignCraft .dcs 脚本 → 可选直接排版导出。
//
// 用法：
//   node build.mjs --list
//   node build.mjs --template poster-a4-photo --values values.json --out designs/demo --slug demo [--run]
//   node build.mjs --template social-1080 --values '{"photo":"designs/assets/x.jpg","title":"墨山"}' --out designs/x --slug x --run
//   node build.mjs --template card-90x54 --values values.json --file-only
//
// 约定：
//   - 模板里的 {{slot}} 取 values 或模板默认值；{{font.serif}} 取 design-tokens.json。
//   - 模板里的 {{#name.id}} / {{#name.story}} 由构建器换算成 batch 的 "$N.id" / "$N.story"（N 是步骤下标）。
//   - ops 里 "when": "<slot>" 的步骤在该槽位为空时整组跳过。
//   - 色板名固定为 Ink / Paper / Accent / Support；print 模式写 CMYK，rgb 模式写 hex。
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import process from "node:process";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CLI =
  process.env.DESIGNCRAFT_CLI ||
  "C:\\Program Files\\ArtCraft\\DesignCraft\\designcraft-cli.exe";

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
    if (next === undefined || next.startsWith("--")) {
      out[key] = true;
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

function loadJson(p) {
  return JSON.parse(readFileSync(p, "utf8").replace(/^\uFEFF/, ""));
}

function deepReplace(value, ctx) {
  if (typeof value === "string") {
    let s = value;
    s = s.replace(/\{\{#([A-Za-z0-9_-]+)\.(id|story|asset)\}\}/g, (m, name, field) => {
      const idx = ctx.indexByName[name];
      if (idx === undefined) throw new Error(`模板引用了未生成的步骤: #${name} (字段 ${field})`);
      return `$${idx}.${field}`;
    });
    s = s.replace(/\{\{font\.([A-Za-z]+)\}\}/g, (m, key) => {
      const f = ctx.tokens.fonts[key];
      if (!f) throw new Error(`design-tokens.json 里没有 font.${key}`);
      return f;
    });
    s = s.replace(/\{\{type\.([A-Za-z0-9]+)\.([A-Za-z]+)\}\}/g, (m, scale, key) => {
      const t = ctx.tokens.typeScales?.[scale]?.[key];
      if (t === undefined) throw new Error(`design-tokens.json 里没有 typeScales.${scale}.${key}`);
      return String(t);
    });
    s = s.replace(/\{\{([A-Za-z0-9_]+)\}\}/g, (m, name) => {
      if (!(name in ctx.values)) throw new Error(`缺少槽位值: ${name}`);
      return String(ctx.values[name] ?? "");
    });
    return s;
  }
  if (Array.isArray(value)) return value.map((v) => deepReplace(v, ctx));
  if (value && typeof value === "object") {
    const o = {};
    for (const [k, v] of Object.entries(value)) o[k] = deepReplace(v, ctx);
    return o;
  }
  return value;
}

function listTemplates() {
  const files = readdirSync(HERE).filter((f) => f.endsWith(".json") && f !== "design-tokens.json");
  for (const f of files) {
    const t = loadJson(path.join(HERE, f));
    console.log(`- ${t.id}: ${t.name}\n    ${t.when}\n    槽位: ${Object.keys(t.slots).join(", ")}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.list) return listTemplates();

  if (!args.template) throw new Error("缺少 --template（用 --list 看有哪些）");
  const tokensPath = args.tokens || path.join(HERE, "design-tokens.json");
  const tokens = loadJson(tokensPath);
  const tplPath = existsSync(args.template) ? args.template : path.join(HERE, `${args.template}.json`);
  const tpl = loadJson(tplPath);

  let values = {};
  if (args.values) {
    values = typeof args.values === "string" && args.values.trim().startsWith("{")
      ? JSON.parse(args.values)
      : loadJson(args.values);
  }
  for (const [name, def] of Object.entries(tpl.slots || {})) {
    if (values[name] === undefined && def.default !== undefined) values[name] = def.default;
    if (def.required && !values[name]) throw new Error(`槽位 ${name} 必填：${def.hint || ""}`);
  }
  if (args.palette) values.palette = args.palette;
  if (args.mode) values.mode = args.mode;
  const paletteId = values.palette || tpl.palette || "ink-night";
  const palette = tokens.palettes[paletteId];
  if (!palette) throw new Error(`未知色板: ${paletteId}（可选 ${Object.keys(tokens.palettes).join(", ")}）`);
  const mode = values.mode || tpl.mode || "cmyk";

  const steps = [];
  const fmt = tpl.format || {};
  const doc = { intent: fmt.intent || "print", pages: 1, facingPages: false, margins: fmt.margins ?? 0 };
  if (fmt.preset) doc.preset = fmt.preset;
  if (fmt.width) {
    doc.width = fmt.width;
    doc.height = fmt.height;
    doc.units = fmt.units || "points";
  }
  if (fmt.bleed !== undefined) doc.bleed = fmt.bleed;
  if (values.title) doc.title = String(values.title);
  steps.push({ cmd: "file.new", params: doc });

  const swatchColors = [
    ["Ink", palette.ink],
    ["Paper", palette.paper],
    ["Accent", palette.accent],
    ["Support", palette.support],
  ];
  for (const [name, c] of swatchColors) {
    if (!c) continue;
    steps.push({ cmd: "swatch.create", params: { name, color: mode === "cmyk" ? c.cmyk : c.hex } });
  }

  // 先收集会被保留的 ops（when 过滤），再映射步骤名 → 下标，最后替换占位符
  const included = (tpl.ops || []).filter((op) => !op.when || String(values[op.when] ?? "").trim() !== "");
  const indexByName = {};
  included.forEach((op, i) => {
    if (op.as) indexByName[op.as] = steps.length + i;
  });
  const ctx = { values, tokens, indexByName };
  for (const op of included) {
    steps.push({ cmd: op.cmd, params: deepReplace(op.params ?? {}, ctx) });
  }

  const outDir = args.out ? path.resolve(args.out) : path.resolve("designs", args.slug || tpl.id);
  const slug = args.slug || tpl.id;
  mkdirSync(outDir, { recursive: true });
  const dcsPath = path.join(outDir, `${slug}.dcs`);

  const lines = [
    `# 由 build.mjs 生成：template=${tpl.id} palette=${paletteId} mode=${mode}`,
    `# 槽位：${JSON.stringify(values).slice(0, 400)}`,
  ];
  for (const s of steps) lines.push(`${s.cmd} ${JSON.stringify(s.params)}`);
  writeFileSync(dcsPath, lines.join("\n") + "\n", "utf8");
  console.log(`[ok] ${steps.length} 步 → ${dcsPath}`);

  if (args["file-only"] || args.print || !args.run) {
    if (args.print) console.log(readFileSync(dcsPath, "utf8"));
    console.log("[hint] 加 --run 直接调用 designcraft-cli 排版并导出 PNG/PDF");
    return;
  }

  const designcraft = path.join(outDir, `${slug}.designcraft`);
  const png = path.join(outDir, `${slug}.png`);
  const pdf = path.join(outDir, `${slug}.pdf`);
  const cliArgs = ["script", dcsPath, "--save", designcraft, "--export", png];
  if ((fmt.intent || "print") === "print") {
    // PDF/X-4：用引擎命令补一步，保证印前标准（--export pdf 不带 X-4 预设）
    const pdfDcs = path.join(outDir, `${slug}-pdf.dcs`);
    writeFileSync(
      pdfDcs,
      [...steps.slice(0, steps.length), { cmd: "file.exportPdf", params: { path: pdf, standard: "x4", bleed: true, marks: false } }]
        .map((s) => `${s.cmd} ${JSON.stringify(s.params)}`)
        .join("\n") + "\n",
      "utf8",
    );
    cliArgs.splice(1, 1, pdfDcs);
  }
  const r = spawnSync(CLI, cliArgs, { encoding: "utf8" });
  const stdout = (r.stdout || "").trim();
  let parsed = null;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    /* 保留原文 */
  }
  if (r.status !== 0) {
    console.error("[fail] designcraft-cli 退出码", r.status);
    console.error(stdout.slice(0, 1200));
    console.error((r.stderr || "").slice(0, 800));
    process.exit(1);
  }
  const summary = {
    template: tpl.id,
    palette: paletteId,
    mode,
    steps: steps.length,
    dcs: dcsPath,
    designcraft,
    png,
    pdf: (fmt.intent || "print") === "print" ? pdf : null,
    completed: parsed?.completed ?? null,
    failed: parsed?.failedIndex ?? null,
  };
  console.log(JSON.stringify(summary, null, 2));
}

main();
