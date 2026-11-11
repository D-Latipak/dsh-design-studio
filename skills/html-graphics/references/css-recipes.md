# HTML/CSS 作图配方（html-graphics）

这个引擎的画布是 Chromium：**你写的 CSS 就是成品**。下面是经过实测的配方、数值与坑。
单位换算、字号阶梯、色板取值仍以 `../graphic-design/templates/design-tokens.json` 与
`../graphic-design/references/layout-and-type.md` 为准，这里只写「HTML 版怎么落地」。

---

## 1. 画布与尺寸

| 用途 | CSS 画布（px） | 渲染命令 | 交付像素 |
|---|---|---|---|
| 小红书 3:4 | 1080 × 1350 | `-Width 1080 -Height 1350` | 1080×1350 |
| 社媒方图 | 1080 × 1080 | 同上 | 1080×1080 |
| 竖屏故事/抖音 | 1080 × 1920 | 同上 | 1080×1920 |
| 公众号首图 | 900 × 383 | 同上 | 900×383 |
| 网页长图 | 1080 × 内容高 | `-Width 1080 -FullPage` | 1080×N |
| 界面稿 / 看板 | 1440 × 900（2×） | `-Width 1440 -Height 900 -Scale 2` | 2880×1800 |
| A4 印刷 | 794 × 1123（=A4@96dpi） | `-Width 210 -Height 297 -Unit mm -Dpi 300` | ≈2480×3508 |
| 名片 90×54mm | 340 × 204 | `-Width 90 -Height 54 -Unit mm -Dpi 300` | ≈1063×638 |

**铁律：CSS 里的 1px 永远是 96dpi 逻辑像素，不是 pt。** 所以 A4 是 794px 宽，不是 595px。
想把 pt 思维搬过来会让画面缩到 157mm。

- 画布外层一律 `width: <W>px; height: <H>px; overflow: hidden`，`html,body{margin:0}`。
- 印刷安全区 3mm ≈ 11.3px（@96dpi）；文字别进 5% 边距。
- 满版元素（背景、光晕、装饰圆）会被 audit 判越界——给它们 `data-audit-ignore` 或放进 `overflow:hidden` 的父级。
- 长图**不要**用 `100vh`；每节写死高度。

## 2. 版式骨架

```css
.grid{display:grid;grid-template-columns:repeat(12,1fr);column-gap:24px;
      padding:64px;align-content:start}
.col-main{grid-column:1/8}.col-aside{grid-column:9/13}
```

- 间距用 4 的倍数（4/8/12/16/24/32/48/64），和 `design-tokens.json` 的 spacing 一致。
- 版式三种起手：**左对齐大标题 + 底部长信息**（海报）、**上图下文/上文下图**（社媒）、
  **多节滚动 + 每节一个论点**（长图）。
- 中文正文 `line-height:1.7`，标题 `1.0–1.1`；英文标题 `0.95–1.05`。
- 中文标题 `letter-spacing: .02–.08em`；正文 `0`；**英文小标签**才用 `.3–.5em` 拉开。
- 竖排中文：`writing-mode: vertical-rl; text-orientation: upright;`（标点会跑偏，少量用）。
- 标题换行平衡：`text-wrap: balance`（Chromium 支持；不支持时手动 `<br>`）。

## 3. 字体

```css
:root{
  --serif:"Noto Serif SC","Source Han Serif SC",serif;
  --sans:"Source Han Sans SC","Noto Sans SC","Microsoft YaHei",sans-serif;
}
```

- 本机已装：`NotoSerifSC-VF` / `NotoSansSC-VF` / `SourceHanSans-Heavy` / `MiSans-Heavy` /
  `AlibabaPuHuiTi-Heavy` / `SmileySans-Oblique` / `PangMenZhengDao` / `LXGWWenKai-Regular` 等。
  **字体族名要用「家族名」**（如 `"Source Han Sans SC"`），用文件名会静默回退到系统衬线。
- 随包字体在 `../graphic-design/assets/fonts/`，加载方式（file:// 下可用，render.mjs 带了
  `--allow-file-access-from-files`）：

```css
@font-face{font-family:"Gloock Local";src:url("../../graphic-design/assets/fonts/Gloock-Regular.ttf") format("truetype")}
```

- **不要** `@import url("https://fonts.googleapis.com/...")`：离线会静默失败、还拖慢首帧。
  需要联网字体时先 `Install-UserFont.ps1` 装到用户字体目录，再用家族名。
- 变量字体可以 `font-variation-settings:"wght" 800` 做超粗标题。
- 中文变豆腐块 = 字体名不存在或没装；交付前 `read_image` 看一眼。

## 4. 色彩与材质（这是 HTML 引擎相对矢量引擎的最大优势）

```css
/* 柔和光晕 */
.glow{background:radial-gradient(60% 45% at 68% 22%, #f7e7c6 0%, rgba(247,231,198,0) 62%)}
/* 双色渐变锥形 */
.conic{background:conic-gradient(from 210deg, #0E1B2A, #7BB51C, #E2603C, #0E1B2A)}
/* 颗粒/砂砾（percent-encoded SVG 噪声，注意引号与 # 必须编码） */
.grain{opacity:.18;mix-blend-mode:overlay;
  background-image:url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='3'/%3E%3C/filter%3E%3Crect width='180' height='180' filter='url(%23n)'/%3E%3C/svg%3E")}
/* 双色调照片：灰度图 + 色层 multiply */
.duo{position:relative;overflow:hidden}
.duo img{filter:grayscale(1) contrast(1.1)}
.duo::after{content:"";position:absolute;inset:0;background:#E2603C;mix-blend-mode:multiply;opacity:.72}
/* 蒙版渐隐 */
.fade{-webkit-mask-image:linear-gradient(180deg,#000 55%,transparent 100%);
      mask-image:linear-gradient(180deg,#000 55%,transparent 100%)}
/* 网点/halftone */
.dots{background-image:radial-gradient(#111 1.2px, transparent 1.3px);background-size:8px 8px}
/* 玻璃 */
.glass{background:rgba(255,255,255,.12);backdrop-filter:blur(14px) saturate(1.2);border:1px solid rgba(255,255,255,.25)}
```

- `mix-blend-mode` 只在同一层叠上下文内起作用；父级加 `isolation:isolate` 可限制范围。
- 大面积 `filter: blur(60px)` 会慢，但 1080 级画布没问题；别叠 20 层。
- 经验值（不是规则）：`#000` 比 `#0E0E10`~`#141418` 更硬，浅底 `#FFF` 比纸色更刺眼；
  用不用纯黑纯白，由 `style-dna.md` 或用户指定决定。
- 色板数量与"大胆动作"没有上限：用户要 10 色、要满屏渐变、要极简一个字，都照做。

## 5. 图像

```css
.photo{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.scrim{position:absolute;inset:0;background:linear-gradient(180deg,transparent 40%,rgba(14,27,42,.85) 100%)}
```

- 压字通常要配 scrim 才读得清；用户有意做低对比、字融进画面时照做，并在交付说明里记一句。
- 高清要求：置入图的实际像素 ≥ 目标像素。1080 宽成品用 2160 宽的图更稳。
- 照片先过 PhotoCraft（裁切/调色/锐化），再进 HTML；HTML 里的 `filter` 只做轻微风格化。
- 有 `<img>` 就必须能加载：audit 会把 404/损坏图列为 error。

## 6. 文字效果

```css
.stroke{color:transparent;-webkit-text-stroke:2px #F2E8D5}
.grad-text{background:linear-gradient(90deg,#E2603C,#C9A227);-webkit-background-clip:text;
           background-clip:text;color:transparent}
.shadow-3d{text-shadow:0 1px 0 #7a5b2f,0 2px 0 #6f5229,0 3px 0 #654a25,0 6px 18px rgba(0,0,0,.45)}
```

- 中文用 `-webkit-text-stroke` 时细笔画会糊，描边 ≥ 2px 才看得出。
- 逐字错位/变形属于字形设计，HTML 只能做「逐字 span 位移 + rotate」，精细改锚点回 VectorCraft。

## 7. 数据图（信息图/长图里最常用）

纯 CSS 柱状：

```html
<div class="bars"><i style="height:62%"></i><i style="height:88%"></i></div>
<style>.bars{display:flex;gap:14px;align-items:flex-end;height:220px}
       .bars i{flex:1;background:linear-gradient(180deg,#4C8DFF,rgba(76,141,255,.2));border-radius:6px 6px 0 0}</style>
```

更复杂的图（折线/散点/面积）用内联 SVG 手写坐标，或让 `scripts/chart.py`（matplotlib）出 SVG：

```
python <skill>/scripts/chart.py --kind line --data data.csv --palette "#E2603C,#0E1B2A" --out chart.svg
```

**所有图表都必须：** 标单位、标最大值、颜色不超过 3 种、去掉网格线与外框（Tufte 数据墨水比）。

## 8. 印刷与 PDF 的边界（必须如实告知用户）

- Chromium 的 PDF 是 **RGB**，没有 CMYK/专色/PDF-X-4；文字可看但**复制出来是乱码**（CJK ToUnicode 缺陷）。
- 因此：**屏幕交付**用 HTML→PNG/PDF 都行；**印刷交付**必须回 DesignCraft/VectorCraft 重排文字与色板，
  或把 HTML 渲染成 300dpi PNG 当**照片层**置入，文字层另排（文字不做位图）。
- 印前检查：导出 PNG 后仍走 `pdfcraft-cli check`/`format-presets.md` 的清单。
- PNG 有透明通道时，印刷需补底色（`--transparent` 只用于 Logo/图标素材）。

## 9. 静默失败点（按出现频率排序）

1. `url(data:image/svg+xml,...)` 里出现未编码的 `<`、`#`、`'` → 整段 CSS 失效。
   **规则**：`<`→`%3C`、`>`→`%3E`、`#`→`%23`，外层用双引号包住整个 url。
2. 把 A4 写成 `595×842`（那是 pt）→ 出图只有 157mm。
3. 用字体**文件名**当 family → 静默回退。
4. `position:fixed` / `100vh` 在长图与 PDF 里会截断或重复。
5. 元素写 `left` 但父级 `overflow:visible` → 横向滚动条把画布挤出（audit 报 `pageOverflowX`）。
6. `letter-spacing` 加在中文大标题上过大会把最后一个字挤出行。
7. audit 的 `tiny` 警告：屏幕稿正文 < 12px（中文 < 14px 基本不可读）。
8. `mix-blend-mode` 与 `filter` 叠加顺序反了 → 颜色发灰。

## 10. 自检清单（交付前）

- [ ] audit `errors: 0`（溢出 / 裁切 / 坏图 / 横向滚动）
- [ ] `read_image` 看过 1× 全图 + 2× 局部
- [ ] 所有文字 ≥ 14px（中文正文）/ 24px（长图）
- [ ] 4–6 色以内，最多 2 个字体族，3 个层级
- [ ] 图片实际像素 ≥ 输出像素
- [ ] 有照片 → 有 scrim / 有对比度
- [ ] 文件名与交付目录符合 `designs/<slug>/`
- [ ] 印品 → 说明「HTML 只出 RGB，印前需重排 CMYK」
