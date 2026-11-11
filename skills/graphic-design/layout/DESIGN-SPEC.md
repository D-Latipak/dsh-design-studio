# 版式规格 design.json · 参考

> **一句话**：你写的是「版式意图」，不是坐标命令。
> 版面由 `layout.mjs` 确定性编译；文字高度由引擎真实字体度量，你猜不出也不用猜。

```
design.json ──lint──▶ 问题清单（秒级，无引擎）
      └────run────▶ 量文字 → 算几何 → 生成 .designcraft → 导出 PNG/PDF ──▶ 报告 JSON
```

工具：`skills/graphic-design/layout/layout.mjs`
示例：`skills/graphic-design/layout/examples/poster-a4.json`

```bash
node layout.mjs lint design.json          # 静态检查，0 引擎
node layout.mjs plan design.json          # 打印每块算出的盒子（调试用）
node layout.mjs run  design.json --out designs/<slug> --slug <slug> --scale 2
```

常用开关：`--fit`（自动缩字）· `--png-bleed`（PNG 带出血）· `--no-png` / `--no-pdf` ·
`--strict`（warn 也算失败）· `--force`（**只在明知有错、要出图排查时用**：带 error 也出片）。

`run` 的 stdout 是一份 JSON 报告，**这就是你的验收依据**，不要为了确认版面去截图：

```json
{ "ok": true,
  "stats": { "blocks": 8, "text": 5, "errors": 0, "warns": 0 },
  "issues": [],
  "out": { "designcraft": "...", "png": "...", "pdf": "...", "px": "1191×1684" },
  "elapsedMs": 305 }
```

**有任一 `error` 就不会 build、不会导出**（`skippedExport: true`），退出码 2。
`issues[].fix` 里是可直接执行的修法（加高到多少 pt / 字号乘多少 / 是不是拼错了 token）。
改完 JSON 再跑一次即可 —— 一轮通常 100–300 毫秒。

---

## 一、顶层字段

| 字段 | 说明 | 默认 |
|---|---|---|
| `title` | 文档名、输出文件名 | `design` |
| `mode` | `print` 走 CMYK 色板 + PDF/X-4；`rgb` 走 hex | `print` |
| `palette` | `design-tokens.json` 的色板名，或内联 `{ink:"#0E1B2A",...}` | 无（fallback 黑白） |
| `colors` | 覆盖/追加色，`{"muted":"#6B7280"}` 或 `{"brand":{"c":0,"m":80,"y":90,"k":0}}` | — |
| `fonts` | `{serif,sans,mono}` 覆盖 | Noto Serif/Sans SC |
| `scale` | 字号阶梯，`{"caption":9,"body":11,"lead":14,"h1":48,"display":220}` | 内置一套 |
| `page` | 见下 | — |
| `blocks` | 块数组，**顺序即叠放顺序（先画的在下面）** | — |

### page

```json
{
  "preset": "A4",          // A6 A5 A4 A3 A2 A1 B5 Letter Legal Tabloid
                           // Square1080 Portrait1080x1350 Story1080x1920 Wide1600x900
  "width": 595.28, "height": 841.89,   // 给了 preset 就不用给；给了会覆盖 preset
  "landscape": false,
  "bleed": 8.5,            // 数字或 {top,right,bottom,left}
  "margins": { "top": 68, "bottom": 68, "left": 68, "right": 68 },
  "columns": 12, "gutter": 12,
  "background": "ink"      // 只用于对比度检查
}
```

单位一律 **pt**（72pt = 1in）。社媒图直接用像素当 pt：`{"width":1080,"height":1080}`。

---

## 二、盒子（box）

每个块用一个盒子定位。四种写法，按需混用：

```jsonc
{ "full": true }                                  // 满版，含出血（做底色用）
{ "abs": [x0, y0, x1, y1] }                       // 绝对坐标（左上、右下）
{ "col": 0, "span": 6, "y": 120 }                 // 栅格：第 0 列起、跨 6 列、顶边 120
{ "col": 0, "span": 6, "anchor": "bottom", "h": 96 }  // 贴内容区底部（页码、信息条）
```

- `col` 从 0 开始，`span` 是列数；列宽由 `page.columns` / `gutter` / 页边距算出。
- **文字块不写 `h` = 自动高度**（引擎量出来多少就是多少）；写了 `h` = 固定框，溢出会报错。
- 不需要写 `w` 或 `x`，除非要用 `abs`。
- 在 `stack`/`row` 里，子块**不写 `y`**，由容器排。

---

## 三、块类型

### text

```json
{
  "id": "title", "kind": "text",
  "box": { "col": 0, "span": 10, "y": 150 },
  "text": "人是功能的\n剩余",
  "font": "serif", "size": 96, "leading": 0.98, "tracking": 20,
  "color": "paper", "align": "left", "valign": "top", "opacity": 0.9
}
```

- `font`：`serif` / `sans` / `mono` 或直接写字体名。
- `size`：数字或 `scale` 里的名字（`caption` `body` `lead` `h1`…）。
- `leading`：倍数（`1.45`）或 `{"pt": 24}`。
- `tracking`：字距，1/1000 em（中文标题常用 20–40，小字标签常用 200–320）。
- `color`：色板键名。
- `\n` 分段。
- **中文必须显式给 `font`**（默认 serif 不一定有你想要的字形）。

### rect / line

```json
{ "id": "bg", "kind": "rect", "box": { "full": true }, "fill": "ink" }
{ "id": "rule", "kind": "rect", "box": { "col": 0, "span": 12, "y": 68, "h": 2 }, "fill": "accent" }
{ "id": "hr", "kind": "line", "box": { "col": 0, "span": 12, "y": 700 }, "weight": 0.5 }
```

`stroke: {"color":"paper","weight":0.5}` 给描边；`radius: 8` 圆角。

### image

```json
{ "id": "photo", "kind": "image", "box": { "col": 0, "span": 12, "y": 0, "h": 380 },
  "src": "assets/photo.jpg", "fit": "fillProportionally" }
```

`src` 相对 spec 文件所在目录；`fit`：`fillProportionally`（默认，裁切填满）或 `stretch`。
`image` 只负责「把已有图片放进框」——图片本身要先经素材关/生图产线拿到。

### stack（纵向流）

```json
{ "id": "info", "kind": "stack",
  "box": { "col": 0, "span": 5, "anchor": "bottom", "h": 96 },
  "gap": 10,
  "children": [
    { "kind": "rect", "box": { "w": 64, "h": 1 }, "fill": "accent" },
    { "kind": "text", "text": "2026.11.08 — 12.20\n沙田 · 城门河畔 B1", "size": "caption", "font": "sans" }
  ]
}
```

子块从容器顶边依次往下排，间距 `gap`，高度用实测值。**这是让长文案自己找位置的办法**——你只给顺序和间距。

### row（横向分栏）

```json
{ "id": "cols", "kind": "row", "box": { "col": 0, "span": 12, "y": 520 },
  "gap": 24, "widths": [2, 1],
  "children": [ { "kind":"text", ... }, { "kind":"text", ... } ] }
```

`widths` 是权重；不给就等分。子块高度由内容定。

---

## 四、校验与报告

**lint 阶段（无引擎，毫秒级）**
- 结构：未知 kind / 缺 text / 缺 box / 缺 y / 未知页面 preset
- 字号：低于可读下限（print 5pt）报 error，低于 7pt 报 warn
- 颜色：token 名不存在（带「是不是想写 X」）、文字与它实际压着的底色对比度 < 1.15 → error；对比度不足 → warn
  （背景按绘制顺序取「覆盖该文字 80% 以上的最后一块矩形」，不是只看页面底色）
- 越界：超出页面+出血 → error；压出安全区 → warn（有意的通栏加 `"margin": false`）
- 固定高溢出（估算，含 tracking）、图片文件不存在 → error
- 两个文字块/图片互压 >35% → warn（色块压字、线压字是正常设计，不报）
- 印刷稿出现纯 RGB 颜色 → warn

**run 阶段（引擎实测，100–300ms）**
- 任何 error 一律**不 build、不导出**（`skippedExport: true`）
- `text.overflow`：**实测**行高超出固定框，`fix` 给「加高到 Npt」或「字号 ×0.93」
- `--fit`：按实测比例逐轮缩字（最多 4 轮）；**缩到 5pt 仍装不下就报 `fit.floor`**，不会再给出「继续缩」的建议

**处理顺序**：先清 `error`，再看 `warn`。重叠警告要判断：文字压图、色块压字是正常设计；两块正文互相压才是错。

---

## 五、怎么写出一份好规格（给 agent 的操作序）

1. 先定 **页面 + 栅格**（几列、边距、出血）——这是全篇的骨架。
2. 定 **字号阶梯**：最多 4 级（display / h1 / body / caption），拉开跨度（至少 4 倍）。
3. 定 **色**：主色 + 纸色 + 一个强调色，够用。全部从色板取，印刷稿别混 RGB。
4. 从上到下写块：底色 → 标题 → 副文 → 主体 → 页脚信息。
5. `lint` → `run` → 看报告 → 改 → 再跑。**不要用截图当验收手段**，只在最终交付前看一眼成品。
6. 需要「换一版风格」时：改 `palette`、`scale`、字体、栅格列数 —— 版式结构不动。

## 六、反模式

- ❌ 用 `abs` 手算每个块 —— 除非你真的在复刻一张具体版式。
- ❌ 给每个文字块都写死 `h` —— 让自动高度工作，只有「必须等高的框」才写 `h`。
- ❌ 一个 `stack` 塞 20 个块 —— 分组，用多个容器。
- ❌ 反复 `run` 试图「看」结果 —— 报告里已经写了溢出多少 pt。
- ❌ 在 spec 里写死颜色 hex（印刷稿）—— 用色板 token。
- ❌ 把图片当装饰随便拉变形 —— `fit` 只给 fillProportionally（裁切）或 stretch（明确要变形）。
