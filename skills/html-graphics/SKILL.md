---
name: html-graphics
description: 用 HTML/CSS/SVG 直接作图并渲染成 PNG/PDF 的画布引擎（Chromium 无头，零依赖）。当用户要长图/信息图/多尺寸套图/小红书或公众号配图/数据图表/界面稿与看板/需要渐变网格·混合模式·噪点颗粒·遮罩等网页级质感/同一版式批量出 N 张文案图时使用；也用于把 SVG 图形与图表精确光栅化、导出 300dpi 印刷用图。印刷交付（CMYK/PDF-X-4）与需要客户在 ArtCraft 里编辑的源文件仍走 DesignCraft/VectorCraft。
---

# HTML 画布（html-graphics）

Chromium 就是绘图引擎：写 HTML/CSS/SVG，无头渲染成 PNG/PDF。
这是**屏幕优先**的产线，擅长渐变、混合模式、噪点、遮罩、排版精细度、批量出图、长图与界面稿；
不擅长 CMYK/专色/可编辑源文件——那两条仍回 DesignCraft / VectorCraft。

## 什么时候用这条产线

**用**：
- 长图、信息图、多节图文（1080×N）；
- 多尺寸套图 / 同版式 N 个文案（改一个变量重渲即可）；
- 数据图表（柱/折线/环，见 `scripts/chart.py`）；
- 界面稿、看板、产品页示意、架构图的「外观稿」；
- 需要网页级质感：渐变网格、噪点颗粒、duotone、玻璃、镜像渐变、复杂遮罩；
- 精确光栅化 SVG（Logo、图标、纹样）到任意像素 + 透明底；
- 印刷稿里的**照片层/底纹层**（300dpi 光栅化后置入 DesignCraft）。

**不用**：
- 直接交付印刷 PDF（Chromium 只出 RGB；文字复制还会乱码）→ 文字层必须回 DesignCraft 重排；
- 客户要在 ArtCraft 里继续编辑的源文件 → `.designcraft` / `.vcraft`；
- 文字要转曲、改锚点、路径文字 → VectorCraft；
- 照片合成/抠图/调色 → PhotoCraft 先处理。

## 五分钟流程

1. **定尺寸** → 查 `references/css-recipes.md` 第 1 节的尺寸表，拿 CSS 画布 px 与渲染参数。
2. **定风格** → 按 `../graphic-design/references/style-research.md`，用用户原话当场联网研究，
   把 DNA 参数写成 `:root` 变量。**本 bundle 没有风格目录**；`design-tokens.json` 只是示例色板，
   用户没指定颜色时才可拿来起手。
3. **找素材** → 按 `../graphic-design/SKILL.md` 的优先级：用户素材 → 免费素材（`Fetch-FreeAsset.ps1`）
   → `generate_image`（提示词走 `../graphic-design/references/image-prompt-recipes.md`）→ 自写 SVG。
   **画面构成听用户的**（`../graphic-design/references/material-pass.md`）：要不要照片、要不要插图、
   全 CSS 渐变行不行，都由用户要求和 `style-dna.md` 决定，**没有"至少一张位图"的配额**。
   需要位图时照片先过 PhotoCraft（裁切/调色/锐化），再进 HTML。
4. **写文件** → `designs/<slug>/<slug>.html`，可从 `templates/` 里挑最接近的一份改：
   `poster-a4.html` / `social-1080.html` / `long-page-1080.html` / `ui-mock-1440.html`。
5. **渲染 + 自检**（一条命令同时出图与审计）：
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Render-Html.ps1" `
     -In designs\slug\slug.html -Out designs\slug\slug.png `
     -Width 1080 -Height 1350 -Scale 2 -Audit
   ```
   - 印刷：`-Width 210 -Height 297 -Unit mm -Dpi 300`（A4 @300dpi ≈ 2481×3509）
   - 长图：`-Width 1080 -FullPage`
   - 单个元素/矢量：`-Selector svg`（或 `#cover`）+ `-Transparent`
   - PDF 预览：`-Pdf`（仅屏幕用；印刷 PDF 走 DesignCraft）
   - `-Audit` 输出 `errors / warnings`，并用退出码 5 表示有阻塞问题。
6. **看图** → `read_image` 看 1× 全图，再 `-Scale 3 -Selector <局部选择器>` 出局部放大看字。
7. **改一轮** → 用户要改的稿先 `New-Revision.ps1` 另存 `-v2`，只改副本。
8. **交付** → PNG（必要时 PDF） + HTML 源文件 + `README.md`（尺寸/色板/字体/假设）；
   印品在说明里写清「HTML 只出 RGB，印前文字回 DesignCraft」。

## audit 判据（0 error 才算过）

| 字段 | 含义 | 处理 |
|---|---|---|
| `overflow[]` | 元素越出画布（不含被 `overflow:hidden` 裁掉的、不含 `[data-audit-ignore]`） | 修版式，或把装饰元素标记忽略 |
| `clipped[]` | 文本被裁（横向 nowrap 溢出 / 纵向 overflow 裁切） | 改宽度、字号或换行 |
| `brokenImages[]` | 图片 404/损坏 | 修路径或重下素材 |
| `pageOverflowX` | 出现横向滚动条 | 通常是绝对定位元素超出 |
| `tiny[]` (warn) | 文字 < 12px | 中文正文应 ≥ 14px |
| `textColors` (warn) | 文本颜色 > 6 种 | 收敛色板 |

装饰性的满版光晕/超大圆要写 `data-audit-ignore`，否则会被判越界。

## 图表

```powershell
python "<skill>\scripts\chart.py" --kind bar --data designs\slug\data.json `
  --out designs\slug\chart.svg --palette "#E2603C,#0E1B2A" --title "季度交付"
```
`--kind bar|line|donut`、`--transparent`、`--size 1200x700`、`--legend`。
输出 SVG 可以直接 `<img>` 进版面（矢量），也可以 `-Selector` 单独光栅化。
数据文件支持 JSON（`labels`/`series`/`unit`）与 CSV（首行表头）。**图表去网格线、标单位、最多 3 色。**

## 参考文件

| 文件 | 内容 |
|---|---|
| `references/css-recipes.md` | 尺寸表、版式骨架、字体、渐变/颗粒/duotone/遮罩、文字效果、图表、印刷边界、**静默失败点**、自检清单 |
| `templates/` | 四份可直接改的起手稿（A4 海报 / 社媒 1080 / 长图 / 界面稿） |
| `../graphic-design/references/style-research.md` | 风格研究：按用户原话当场联网查真实设计 → DNA（无内置风格目录） |
| `../graphic-design/references/quality-checklist.md` | 交付检查（硬伤 + 用户要求是否落实；不评判风格） |
| `../graphic-design/references/lettering-and-display-type.md` | 字形路线（HTML 只做 span 位移/描边，精细改字形回 VectorCraft） |

## 六条最容易翻车的点

1. **单位**：CSS px 是 96dpi，不是 pt；A4 = 794×1123px，写成 595×842 会缩成 157mm。
2. **字体**：用家族名（`"Source Han Sans SC"`），不要用文件名；离线不要 `@import` Google Fonts。
3. **data URI**：SVG 背景里的 `<`、`>`、`#`、`'` 必须百分号编码，否则整段 CSS 失效。
4. **长图**：别用 `100vh`/`position:fixed`，每节写死高度。
5. **PDF**：Chromium PDF 是 RGB，中文复制乱码——印刷交付必须回 DesignCraft 重排文字。
6. **audit 不是审美**：它只查越界/裁切/坏图/字号；好不好看由用户的要求和 `style-dna.md` 决定，
   本 bundle 不对风格打分。
