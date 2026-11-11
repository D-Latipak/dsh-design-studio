#!/usr/bin/env node
// 静态检查：不启动引擎，纯几何 + 颜色 + 结构。
// 输入是「已经算好最终盒子」的叶子块（computeGeometry 的输出），
// 因此这里的越界/重叠判断与真正排版完全一致。
// 有引擎实测高度时（b.measuredH != null）以实测为准，不再估算。
import fs from "node:fs";
import path from "node:path";
import { contrastRatio, leadingPt } from "./spec.mjs";

const MIN_PT = { print: 5, web: 4, mobile: 4 };
const WARN_PT = { print: 7, web: 9, mobile: 9 };

function overlapArea(a, b) {
  const w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
  const h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
  return w > 0.5 && h > 0.5 ? w * h : 0;
}

const area = (b) => Math.max(0.01, b.w * b.h);
const contains = (outer, inner) => overlapArea(outer, inner) / area(inner) >= 0.8;
const covers = (box, page) => box.w * box.h >= page.w * page.h * 0.95;

/**
 * @param {{ctx, spec, leaves, errors?}} model
 * @returns {{issues: Array, stats: object}}
 */
export function lint(model, opts = {}) {
  const { ctx, spec, leaves, errors = [] } = model;
  const issues = [...errors];
  const push = (level, code, where, msg, fix) => issues.push({ level, code, where, msg, ...(fix ? { fix } : {}) });
  const page = ctx.page;
  const minPt = MIN_PT[ctx.mode] ?? 5;
  const warnPt = WARN_PT[ctx.mode] ?? 7;

  // 页面底色
  let pageBg = { kind: "hex", hex: "#FFFFFF" };
  if (spec?.page?.background) {
    const p = ctx.palette[spec.page.background];
    if (p) pageBg = { kind: "token", name: spec.page.background, ...p };
  }

  const colorHex = (c) => (c?.kind === "none" || !c ? null : c.hex || null);

  // 已绘制的不透明矩形（按绘制顺序），用来判断文字实际压在哪块颜色上
  const painted = [];

  for (const b of leaves) {
    const where = b.where;
    const box = b.box;

    // 文字取「覆盖它 80% 以上的、最后绘制的那块矩形」为背景
    let bg = pageBg;
    if (b.kind === "text") {
      for (let i = painted.length - 1; i >= 0; i--) {
        if (contains(painted[i].box, box)) {
          bg = painted[i].fill;
          break;
        }
      }
    }

    if (b.kind === "text") {
      if (!b.text.trim()) push("warn", "text.empty", where, "空文字块", "删掉它，或补内容");

      if (b.size < minPt) push("error", "text.tooSmall", where, `${b.size}pt 小于可读下限 ${minPt}pt`, "放大字号或删掉这行");
      else if (b.size < warnPt) push("warn", "text.small", where, `${b.size}pt 偏小（<${warnPt}pt）`, "确认这是注释/边注再保留");

      // 对比度：与它实际压着的那块底色比
      const bgHex = colorHex(bg);
      if (b.color.kind !== "none" && bgHex) {
        const ratio = contrastRatio(colorHex(b.color), bgHex);
        if (ratio != null) {
          if (ratio < 1.15) push("error", "text.invisible", where, `文字与背景几乎同色（对比度 ${ratio.toFixed(2)}，背景 ${bg.name || bg.hex}）`, "换颜色，或检查绘制顺序（文字要先于盖住它的色块）");
          else if (ratio < (b.size >= 24 ? 3 : 4.5)) {
            push("warn", "text.contrast", where, `对比度 ${ratio.toFixed(2)} < ${b.size >= 24 ? 3 : 4.5}（背景 ${bg.name || bg.hex}）`, "加深/提亮文字或背景");
          }
        }
      }

      // 溢出：有实测用实测，没有才估算
      if (b.fixedH != null) {
        const lh = leadingPt(b.size, b.leading);
        let need;
        let how;
        if (b.measuredH != null) {
          need = b.measuredH;
          how = "实测";
        } else {
          const charW = b.size * (1 + (b.tracking || 0) / 1000);
          let lines = 0;
          for (const para of String(b.text).split("\n")) {
            const units = [...para].reduce((s, ch) => s + (/[\u3000-\u9fff\uff00-\uffef]/.test(ch) ? 1 : 0.55), 0);
            lines += Math.max(1, Math.ceil((units * charW) / box.w));
          }
          need = lines * lh;
          how = `估算 ${lines} 行`;
        }
        if (need > b.fixedH + 0.5) {
          push("error", "text.overflow", where, `${how} ≈ ${need.toFixed(0)}pt，框高 ${b.fixedH.toFixed(0)}pt`, `框加高到 ${Math.ceil(need)}pt，或用 --fit 自动缩字（引擎实测）`);
        }
      }
    }

    if (b.kind === "line" && box.w <= 0.2) push("error", "line.width", where, "线宽为 0", "给 w 或改用 rect");

    // 越界（含出血）
    const inPage =
      box.x >= -page.maxBleed - 0.5 &&
      box.y >= -page.maxBleed - 0.5 &&
      box.x + box.w <= page.w + page.maxBleed + 0.5 &&
      box.y + box.h <= page.h + page.maxBleed + 0.5;
    if (!inPage) {
      push("error", "box.outOfPage", where, `盒子 [${box.x.toFixed(0)},${box.y.toFixed(0)} ${box.w.toFixed(0)}×${box.h.toFixed(0)}] 超出页面/出血`, "收进页面，或用 box.full 做满版底");
    }

    // 页边距（满版 / 显式 margin:false 的除外）
    if (b.raw?.margin !== false && !b.raw?.box?.full && !covers(box, page)) {
      const c = page.content;
      const outside = box.x < c.x - 0.5 || box.y < c.y - 0.5 || box.x + box.w > c.x + c.w + 0.5 || box.y + box.h > c.y + c.h + 0.5;
      if (outside) push("warn", "box.outsideMargin", where, "压出了页边距（安全区）", "是有意的出血/通栏就加 margin:false，否则用 col/span 对齐网格");
    }

    // 图片存在性（缺图是硬错：出片会是一块空白）
    if (b.kind === "image" && b.src && !/^(https?:|data:)/.test(b.src)) {
      const abs = path.isAbsolute(b.src) ? b.src : path.resolve(opts.baseDir || process.cwd(), b.src);
      if (!fs.existsSync(abs)) push("error", "image.missing", where, `找不到图片 ${b.src}`, "先下载/生成到 designs/assets/ 再引用（相对路径按 spec 所在目录解析）");
    }

    if (b.kind === "rect" && b.fill.kind !== "none") painted.push({ box, fill: b.fill });
  }

  // ---- 重叠：只报「两个文字块互压」这类真错误；色块压字/线压字是正常设计 ----
  for (let i = 0; i < leaves.length; i++) {
    const a = leaves[i];
    if (!["text", "image"].includes(a.kind)) continue;
    for (let j = i + 1; j < leaves.length; j++) {
      const b = leaves[j];
      if (!["text", "image"].includes(b.kind)) continue;
      const ov = overlapArea(a.box, b.box);
      if (ov <= 0) continue;
      const small = Math.min(area(a.box), area(b.box));
      if (ov / small > 0.35) {
        push("warn", "box.overlap", `${a.id} × ${b.id}`, `重叠 ${((ov / small) * 100).toFixed(0)}%`, "两段内容互相压住通常不对；确认是有意的叠压设计");
      }
    }
  }

  // ---- 印刷色 ----
  if (ctx.mode === "print") {
    const hexOnly = new Set();
    for (const b of leaves) {
      for (const c of [b.fill, b.color]) {
        if (c && c.kind === "hex" && !c.cmyk) hexOnly.add(c.hex);
      }
    }
    if (hexOnly.size) push("warn", "color.rgbInPrint", "colors", `${hexOnly.size} 个颜色只有 RGB、没有 CMYK`, "印刷稿用 design-tokens 的 CMYK 色板，或给颜色加 cmyk");
  }

  const colors = new Set();
  for (const b of leaves) {
    for (const c of [b.fill, b.color]) {
      if (c && c.kind !== "none") colors.add(c.kind === "token" ? c.name : c.hex || JSON.stringify(c.cmyk));
    }
  }

  return {
    issues,
    stats: {
      blocks: leaves.length,
      text: leaves.filter((b) => b.kind === "text").length,
      images: leaves.filter((b) => b.kind === "image").length,
      colors: colors.size,
      errors: issues.filter((i) => i.level === "error").length,
      warns: issues.filter((i) => i.level === "warn").length,
    },
  };
}
