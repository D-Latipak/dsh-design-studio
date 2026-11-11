#!/usr/bin/env node
// 设计规格（Design Spec）→ 规范化模型
//
// 这一层的职责：把 agent 写的「声明式设计稿」变成
//   { 页面几何、色板、字体阶梯、每个块的最终盒 }
// 不含任何引擎调用；纯函数，可在没有 DesignCraft 的机器上跑。
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const TOKENS_PATH = path.resolve(HERE, "..", "..", "templates", "design-tokens.json");

export const PAGE_PRESETS = {
  A6: [297.64, 419.53],
  A5: [419.53, 595.28],
  A4: [595.28, 841.89],
  A3: [841.89, 1190.55],
  A2: [1190.55, 1683.78],
  A1: [1683.78, 2383.94],
  B5: [498.9, 708.66],
  Letter: [612, 792],
  Legal: [612, 1008],
  Tabloid: [792, 1224],
  Square1080: [1080, 1080],
  Portrait1080x1350: [1080, 1350],
  Story1080x1920: [1080, 1920],
  Wide1600x900: [1600, 900],
};

const DEFAULT_FONTS = { serif: "Noto Serif SC", sans: "Noto Sans SC", mono: "JetBrains Mono" };
const DEFAULT_SCALE = { micro: 7, caption: 9, body: 11, lead: 14, h3: 18, h2: 26, h1: 48, title: 96, display: 220 };

function readJson(p) {
  return JSON.parse(readFileSync(p, "utf8").replace(/^\uFEFF/, ""));
}

export function loadTokens(p = TOKENS_PATH) {
  try {
    return readJson(p);
  } catch {
    return { fonts: DEFAULT_FONTS, palettes: {}, spacing: [4, 8, 12, 16, 24, 32, 48, 64] };
  }
}

const num = (v, d) => (typeof v === "number" && Number.isFinite(v) ? v : d);

/** 四边值：数字 / 单值 / {top,right,bottom,left} / [t,r,b,l] */
function edges(v, d = 0) {
  if (v == null) return { top: d, right: d, bottom: d, left: d };
  if (typeof v === "number") return { top: v, right: v, bottom: v, left: v };
  if (Array.isArray(v)) return { top: v[0] ?? d, right: v[1] ?? d, bottom: v[2] ?? d, left: v[3] ?? d };
  return {
    top: num(v.top, d),
    right: num(v.right, num(v.outside, d)),
    bottom: num(v.bottom, d),
    left: num(v.left, num(v.inside, d)),
  };
}

function hexToRgb(hex) {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(hex).trim());
  if (!m) return null;
  let h = m[1];
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

/** 简易 sRGB → CMYK（只用于 lint 提示与缺省色板；精确值走 design-tokens.json） */
function rgbToCmyk([r, g, b]) {
  const k = 1 - Math.max(r, g, b) / 255;
  if (k >= 1) return { c: 0, m: 0, y: 0, k: 100 };
  const f = (v) => Math.round(((1 - v / 255 - k) / (1 - k)) * 100);
  return { c: f(r), m: f(g), y: f(b), k: Math.round(k * 100) };
}

export function relativeLuminance([r, g, b]) {
  const f = (v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}

export function contrastRatio(hexA, hexB) {
  const a = hexToRgb(hexA);
  const b = hexToRgb(hexB);
  if (!a || !b) return null;
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/**
 * 载入并规范化 spec。
 * 返回 { spec, page, ctx, blocks, errors } —— 只做结构与几何展开，不做审美判断。
 */
export function normalize(spec, opts = {}) {
  const errors = [];
  const tokens = loadTokens(opts.tokensPath);
  const mode = spec.mode || spec.page?.mode || "print";
  const intent = spec.intent || (mode === "print" ? "print" : "web");

  // ---- 页面 ----
  const pageIn = spec.page || {};
  let pw, ph;
  if (pageIn.preset) {
    const p = PAGE_PRESETS[pageIn.preset];
    if (!p) errors.push({ level: "error", code: "page.preset", where: "page", msg: `未知页面预设 ${pageIn.preset}（可用：${Object.keys(PAGE_PRESETS).join(", ")}）` });
    else [pw, ph] = p;
  }
  pw = num(pageIn.width, pw ?? 595.28);
  ph = num(pageIn.height, ph ?? 841.89);
  if (pageIn.landscape) [pw, ph] = [ph, pw];

  const bleed = edges(pageIn.bleed, 0);
  const margins = edges(pageIn.margins ?? 48, 48);
  const cols = num(pageIn.columns, 1);
  const gutter = num(pageIn.gutter, 12);

  const maxBleed = Math.max(bleed.top, bleed.right, bleed.bottom, bleed.left);
  const content = {
    x: margins.left,
    y: margins.top,
    w: pw - margins.left - margins.right,
    h: ph - margins.top - margins.bottom,
  };
  if (content.w <= 0 || content.h <= 0) {
    errors.push({ level: "error", code: "page.margins", where: "page", msg: `页边距吃掉整个版面（内容区 ${content.w.toFixed(1)}×${content.h.toFixed(1)}pt）` });
  }
  const colW = (content.w - (cols - 1) * gutter) / cols;

  // ---- 色板 ----
  const paletteName = spec.palette || spec.page?.palette;
  const palettes = tokens.palettes || {};
  let palette = {};
  if (typeof paletteName === "string" && palettes[paletteName]) {
    const p = palettes[paletteName];
    for (const [k, v] of Object.entries(p)) {
      if (v && typeof v === "object" && v.hex) palette[k] = { hex: v.hex, cmyk: v.cmyk };
    }
  } else if (paletteName && typeof paletteName === "object") {
    for (const [k, v] of Object.entries(paletteName)) {
      if (typeof v === "string") {
        const rgb = hexToRgb(v);
        palette[k] = { hex: v, cmyk: rgb ? rgbToCmyk(rgb) : undefined };
      } else if (v?.hex) palette[k] = v;
    }
  } else if (paletteName) {
    errors.push({ level: "error", code: "palette.unknown", where: "palette", msg: `色板 ${paletteName} 不存在（可用：${Object.keys(palettes).join(", ") || "无"}）` });
  }
  // spec.colors 覆盖/追加
  for (const [k, v] of Object.entries(spec.colors || {})) {
    if (typeof v === "string") {
      const rgb = hexToRgb(v);
      palette[k] = { hex: v, cmyk: rgb ? rgbToCmyk(rgb) : undefined };
    } else if (v?.hex) palette[k] = v;
    else if (v?.c || v?.m || v?.y || v?.k) palette[k] = { hex: undefined, cmyk: v };
  }
  if (!Object.keys(palette).length) {
    palette = { ink: { hex: "#111111" }, paper: { hex: "#FFFFFF" } };
  }

  const fonts = { ...DEFAULT_FONTS, ...(tokens.fonts || {}), ...(spec.fonts || {}) };
  const scale = { ...DEFAULT_SCALE, ...(spec.scale || {}) };

  const ctx = {
    page: { w: pw, h: ph, bleed, margins, cols, gutter, colW, content, maxBleed },
    mode,
    intent,
    palette,
    paletteName: typeof paletteName === "string" ? paletteName : "(inline)",
    fonts,
    scale,
    spacing: tokens.spacing || [4, 8, 12, 16, 24, 32, 48, 64],
    tokensPath: opts.tokensPath || TOKENS_PATH,
  };

  const blocks = (spec.blocks || []).map((b, i) => normalizeBlock(b, i, ctx, errors, "blocks"));
  return { spec, ctx, blocks, errors };
}

export function resolveColor(v, ctx, errors, where) {
  if (v == null || v === "" || v === "none" || v === "[None]") return { kind: "none" };
  if (typeof v === "object") {
    if (v.cmyk) return { kind: "cmyk", cmyk: v.cmyk };
    if (v.hex) return colorFromHex(v.hex, ctx, errors, where);
    return { kind: "cmyk", cmyk: v };
  }
  if (typeof v === "string" && ctx.palette[v]) return { kind: "token", name: v, ...ctx.palette[v] };
  if (typeof v === "string" && (/^#[0-9a-f]{3}$/i.test(v) || /^#[0-9a-f]{6}$/i.test(v) || /^[0-9a-f]{6}$/i.test(v))) {
    return colorFromHex(v, ctx, errors, where);
  }
  const names = Object.keys(ctx.palette);
  const hint = suggest(v, names);
  errors.push({
    level: "error",
    code: "color.unknown",
    where,
    msg: `颜色 "${v}" 不是色板 ${ctx.paletteName} 的 token（可用：${names.join(", ")}）${hint ? `；是不是想写 "${hint}"？` : ""}`,
    fix: hint ? `改成 "${hint}"` : "用上面的 token 名，或写 #rrggbb",
  });
  return { kind: "none" };
}

/** 编辑距离 ≤2 的最近候选，用于拼写提示 */
function suggest(word, list) {
  let best = null;
  let bestD = 3;
  for (const w of list) {
    const d = levenshtein(String(word).toLowerCase(), w.toLowerCase());
    if (d < bestD) {
      bestD = d;
      best = w;
    }
  }
  return best;
}

function levenshtein(a, b) {
  const m = a.length;
  const n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[n];
}

function colorFromHex(hex, ctx, errors, where) {
  const rgb = hexToRgb(hex);
  if (!rgb) {
    errors.push({ level: "error", code: "color.hex", where, msg: `非法 hex 颜色 ${hex}` });
    return { kind: "none" };
  }
  return { kind: "hex", hex, rgb, cmyk: rgbToCmyk(rgb) };
}

/** 给色板色一个稳定的 swatch 名 */
export function swatchName(color, ctx) {
  if (color.kind === "token") return capitalize(color.name);
  if (color.kind === "cmyk") return `C${Math.round(color.cmyk.c)}M${Math.round(color.cmyk.m)}Y${Math.round(color.cmyk.y)}K${Math.round(color.cmyk.k)}`;
  if (color.kind === "hex") return color.hex.replace("#", "").toUpperCase();
  return null;
}

const capitalize = (s) => s.charAt(0).toUpperCase() + s.slice(1);

function normalizeFont(v, ctx, errors, where) {
  if (!v) return ctx.fonts.serif;
  if (ctx.fonts[v]) return ctx.fonts[v];
  return v; // 直接写字体名
}

function fontSize(v, ctx, errors, where) {
  if (typeof v === "number") return v;
  if (typeof v === "string" && typeof ctx.scale[v] === "number") return ctx.scale[v];
  errors.push({ level: "error", code: "type.size", where, msg: `字号 ${JSON.stringify(v)} 既不是数字也不是字号阶梯里的名字（${Object.keys(ctx.scale).join(", ")}）` });
  return 12;
}

/** 支持 {col, span}、{x,y,w,h}、{abs:[x0,y0,x1,y1]}、{full:true}；y/h 可为空（由流程决定） */
export function resolveBox(box, ctx, errors, where) {
  const { content, colW, gutter, cols, w: pw, h: ph, maxBleed } = ctx.page;
  if (!box) {
    // stack/row 的子块可以完全不写 box（x/w 由容器给）；顶层缺 box 由 computeGeometry 报错
    return { x: null, y: null, w: null, h: null };
  }
  if (box.full) {
    return { x: -maxBleed, y: -maxBleed, w: pw + maxBleed * 2, h: ph + maxBleed * 2 };
  }
  if (box.abs) {
    const [x0, y0, x1, y1] = box.abs;
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }
  const out = {};
  if (box.col != null) {
    const col = num(box.col, 0);
    const span = num(box.span, 1);
    if (col < 0 || col >= cols) errors.push({ level: "error", code: "box.col", where, msg: `col ${col} 超出 0..${cols - 1}` });
    if (span < 1) errors.push({ level: "error", code: "box.span", where, msg: `span ${span} 必须 ≥ 1` });
    out.x = content.x + col * (colW + gutter);
    out.w = span * colW + (span - 1) * gutter;
  } else {
    // 没写 x/w 的（stack/row 的子块）留给容器填
    out.x = box.x != null ? num(box.x, null) : null;
    out.w = box.w != null ? num(box.w, null) : null;
  }
  if (box.anchor === "bottom") {
    const h = num(box.h, 0);
    out.h = h;
    out.y = content.y + content.h - h - num(box.offset, 0);
  } else {
    out.y = box.y != null ? num(box.y, null) : null;
    out.h = box.h != null && box.h !== "auto" ? num(box.h, null) : null;
  }
  return out;
}

function normalizeBlock(b, i, ctx, errors, parentPath = "blocks") {
  const id = b.id || `${b.kind || "block"}-${i}`;
  const where = `${parentPath}[${i}]${b.id ? ` (${b.id})` : ""}`;
  if (!b.kind) errors.push({ level: "error", code: "block.kind", where, msg: "块缺少 kind（text/rect/line/image/stack/row）" });
  const kind = b.kind;
  const box = resolveBox(b.box, ctx, errors, where);
  const common = { id, kind, where, box, raw: b, opacity: num(b.opacity, 1) };

  if (kind === "text") {
    if (typeof b.text !== "string") errors.push({ level: "error", code: "text.missing", where, msg: "text 块缺少 text 字符串" });
    return {
      ...common,
      text: b.text ?? "",
      font: normalizeFont(b.font, ctx, errors, where),
      fontStyle: b.fontStyle || null,
      size: fontSize(b.size ?? "body", ctx, errors, where),
      leading: b.leading ?? 1.45,
      tracking: num(b.tracking, 0),
      color: resolveColor(b.color ?? "ink", ctx, errors, where),
      align: b.align || "left",
      valign: b.valign || "top",
      autoH: box.h == null,
      fixedH: box.h,
    };
  }
  if (kind === "rect" || kind === "line") {
    const h = kind === "line" ? num(b.weight, 0.5) : box.h;
    return {
      ...common,
      box: kind === "line" ? { x: box.x, y: box.y, w: box.w, h } : box,
      fill: resolveColor(b.fill ?? (kind === "line" ? "ink" : null), ctx, errors, where),
      stroke: b.stroke ? { color: resolveColor(b.stroke.color ?? "ink", ctx, errors, where), weight: num(b.stroke.weight, 0.5) } : null,
      radius: num(b.radius, 0),
    };
  }
  if (kind === "image") {
    if (!b.src) errors.push({ level: "error", code: "image.src", where, msg: "image 块缺少 src" });
    return { ...common, src: b.src, fit: b.fit || "fillProportionally" };
  }
  if (kind === "stack" || kind === "row") {
    const children = (b.children || []).map((c, j) => normalizeBlock(c, j, ctx, errors, `${where}.children`.replace(`${b.id ? ` (${b.id})` : ""}`, "")));
    return { ...common, gap: num(b.gap, 12), children, widths: b.widths || null, align: b.align || "stretch" };
  }
  errors.push({ level: "error", code: "block.kind", where, msg: `未知 kind ${kind}` });
  return common;
}

/** 递归展开成叶子块（用于统计与静态描边） */
export function walk(blocks, fn, parent = null) {
  for (const b of blocks) {
    fn(b, parent);
    if (b.children) walk(b.children, fn, b);
  }
}

/** 单位：leading 可以是倍数（1.45）或 {pt: 24} */
export function leadingPt(size, leading) {
  if (leading && typeof leading === "object") return num(leading.pt, size * 1.4);
  return size * num(leading, 1.4);
}
