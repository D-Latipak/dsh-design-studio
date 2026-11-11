# DesignCraft 命令配方（0.19.0 基线；部分配方在 0.14.0 上验证）

> **本文件里的任何参数，若与 `designcraft-cli commands` / `list_commands` 的实时输出冲突，以命令目录为准。**
> 这是全库基线最旧的一份配方——不要因为这里写着就照抄，先查一次。

本文件里的配方最初在本机 `designcraft-cli 0.14.0` + `designcraft-cli mcp` 上跑通过；
2026-11-09 升级到 **0.19.0** 后，命令 id 只增不减（542 → 555，无删除），已抽查核心链路仍可用。
命令 id 共 555 个，完整目录用 `list_commands` 或 `designcraft-cli commands` 查；参数以 `params` 字段为准。
0.19 新增的与本线相关：`file.exportBatch` / `file.exportPresets` / `file.saveExportPreset`（批量导出与预设）、
`layout.alternate.*`、`object.clearFittingOptions`、`path.deletePoints`。

## 0. 环境与坐标（先记牢）

- 单位：**pt**（1 mm = 2.8346 pt）。A4 = 595.28 × 841.89 pt。
- 坐标：spread 空间，原点 = 页面左上，**y 向下**。
- `frame.create` 的 `rect` 是 **两个角点 [x0, y0, x1, y1]**（不是 x,y,w,h）。
- 带出血的满版矩形：A4 出血 8.5 pt → `[-8.5, -8.5, 603.78, 850.39]`。
- MCP 工具输出里的 `{id, story}`：`id` 是对象，`story` 是它的文字故事（文字帧才有）。

## 1. 新建文档

MCP：`new_document {"preset":"A4","intent":"print","pages":1,"facingPages":false,"margins":0,"bleed":8.5,"title":"…"}`
CLI：`file.new {"preset":"A4", …}`（同样参数）。自定义尺寸用 `width`/`height`，不要同时又给 preset。

可用预设（`file.presets` 实测）：Letter / Legal / Tabloid / A0–A6 / B5 / Business Card / Postcard / Web 1920×1080 / Mobile 1080×1920 等。

## 2. 建色板（**必须**先建，后面 fill 用名字）

```json
swatch.create {"name":"Ink","color":"#0E1B2A"}                        // RGB：屏幕稿
swatch.create {"name":"Ink","color":{"c":90,"m":70,"y":40,"k":55}}     // CMYK：印刷稿
```
返回值 `{"name":"Ink"}`。`fill` 参数接受**色板名**（不是 hex）；直接用 hex 要用 `object.color {"color":"#0E1B2A"}`。

**印刷品一律用 CMYK 建色板**（`{c,m,y,k}`，0–100）。全部 RGB 时导出 PDF/X-4 会给
`PDF/X-4: RGB fills or strokes on page 1: under a CMYK output intent RGB needs an ICC profile` 警告，
`validate-pdf` 也可能判不过；CMYK 色板实测得到 `warnings: []` + `valid: true`。
屏幕稿（社媒/网页）用 RGB 即可。

## 3. 建对象（底色 / 色块 / 圆）

```json
frame.create {"rect":[-8.5,-8.5,603.78,850.39],"content":"graphic"}          → {"id":7}
object.fill  {"swatch":"Ink","ids":["$5.id"]}                                 → {"changed":1}
frame.create {"rect":[330,430,720,820],"shape":"ellipse","content":"graphic"} → {"id":8}
object.fill  {"swatch":"Accent","ids":["$7.id"]}
object.opacity {"opacity":0.16,"ids":["$7.id"]}
```
`shape`: `rectangle|ellipse|polygon`（polygon 用 `sides`）。渐变用 `object.gradient`。

## 4. 建文字并上样式（**关键：必须先把整段文字选中**）

`frame.create` 带 `text` 只会写字，新帧处于「对象选中」状态，直接 `type.char` **不会**生效。
必须先用下面任一方式建立**文字选区**，再改样式：

- 已知帧 id：`text.selectStory {"frame":"$15.id","point":[200,250]}` → `{"anchor":0,"focus":12,"story":13}`（`point` 是帧内任意一点）
- 已知道故事 id 与字节长度：`text.select {"story":13,"anchor":0,"focus":12}`
- 之后再 `type.char` / `type.para` 就作用于整段：

```json
frame.create {"rect":[58,168,545,330],"content":"text","text":"静默生长"}     → {"id":12,"story":13}
text.selectStory {"frame":"$15.id","point":[200,250]}
type.char {"attrs":{"fontFamily":"Noto Serif SC","size":112,"tracking":30,"fill":"Paper"}}
type.para {"attrs":{"align":"left"}}
```

**中文字体必须显式设置。** 新建文本默认字体是 bundled 的 `Source Serif 4`（无中文字形），不设 `fontFamily` 时导出的中文是**方框豆腐块**。本机可用且已实测 `matchStatus: exact` 的中文字体：

| fontFamily | 风格 | 说明 |
|---|---|---|
| `Noto Sans SC` | 黑体 | 正文/信息首选，可变字重 |
| `Noto Serif SC` | 宋体 | 大标题首选，有书卷气 |
| `Microsoft YaHei` | 黑体 | Windows 系统字体 |
| `SimSun` / `SimHei` / `KaiTi` | 宋/黑/楷 | 系统字体 |
| `DengXian` | 黑体 | 系统字体 |

设完用 `font.list {}` 复核：`"matchStatus":"exact"`、`"missing":false` 才算成功；出现 `missing` / `replacementFamily` 就是被替换了（中文会变豆腐块），换一个字体重设。

`tracking` 单位 = 1/1000 em（`30` = +0.03em）；`leading` 用 `{"kind":"points","value":22}`，或 `{"kind":"auto"}`。
`type.char` 支持：`fontFamily, fontStyle, size, leading, tracking, kerning, fill, capitalization, underline…`
`type.para` 支持：`align, leftIndent, firstLineIndent, spaceBefore, spaceAfter, hyphenate, …`

## 5. 用 batch 一次成型（推荐）

`batch {"commands":[ … ]}` 按顺序执行，参数里用 `"$N.path"` 引用第 N 步（0 基）的结果：

```json
{"commands":[
  {"command":"frame.create","params":{"rect":[-8.5,-8.5,603.78,850.39],"content":"graphic"}},
  {"command":"object.fill","params":{"swatch":"Ink","ids":["$0.id"]}},
  {"command":"frame.create","params":{"rect":[58,168,545,330],"content":"text","text":"静默生长"}},
  {"command":"text.selectStory","params":{"frame":"$2.id","point":[200,250]}},
  {"command":"type.char","params":{"attrs":{"fontFamily":"Noto Serif SC","size":112,"tracking":30,"fill":"Paper"}}}
]}
```

失败会返回 `failedIndex` / `failedCommand` / `error`；已执行的步骤不回滚（用 `edit.undo` 撤销）。

## 6. 看稿

- `render_page {"page":0,"scale":1}` → 直接返回 PNG 图像内容（约 595×842 px），用来快速看结构。
- `export_png {"page":0,"path":"…\\x.png","scale":2}` → 写文件，A4 得到 1190×1684 px。**交付用这个**（scale 2~3）。
- 改稿循环：`render_page` → `read_image` → 发现问题 → `execute`/`batch` 修 → 再 `render_page`。

## 7. 保存与导出

- `save_document {"path":"…\\<slug>.designcraft"}` —— 可编辑源文件。
- 印刷 PDF：`execute {"command":"file.exportPdf","params":{"path":"…\\x.pdf","standard":"x4","marks":false,"bleed":true}}`
  （`standard`: `none|x4|x1a|a2b`；`bleed:true` 带上出血；返回 `{path,bytes,pages,warnings}`）
  验证：`designcraft-cli validate-pdf x.pdf` → 目标 `{"valid":true,"issues":[],"warnings":[]}`。
  不达标时先查配色是否 CMYK、字体是否嵌入、PDF 版本。

## 8. 常用附属命令

| 需求 | 命令 |
|---|---|
| 改单个文本内容 | `set_story_text {"story":13,"text":"新文字"}`（\n = 换段） |
| 读文本 | `get_story {"story":13}` → 长度是 UTF-8 **字节**数 |
| 置入图片（PhotoCraft 处理后的成品图） | `execute {"command":"file.place","params":{"path":"…\\photo-graded.jpg","x":-8.5,"y":-8.5,"width":603.78}}` → `{asset, id}`（宽定高随比例） |
| 照片压底 + 压字过渡 | 照片上叠一个矩形，再 `object.gradient`（见下方「照片版式」） |
| 置入到已有图框 | `place_image {"path":"…","frame":<id>}` |
| 图片适配 | `object.fit {"mode":"fillProportionally","ids":[8]}` |
| 对齐 | `object.align {"edge":"left","to":"margins","ids":[…]}` |
| 层序 | `object.arrange {"to":"front","ids":[8]}` |
| 二维码 | `object.qrCode {"content":"https://…","rect":[420,700,520,800]}` → `{id,content}` |
| 文档摘要 | `inspect_document {}` → 页、对象 bounds、故事 overset、色板、选中 |
| 查字体状态 | `font.list {}` |
| 页面设置 | `layout.marginsAndColumns {"margins":36,"columns":12,"gutter":11.3}` |
| 导出 HTML/EPUB/PPTX | `file.exportHtml` / `file.exportEpub` / `file.exportPptx` |

### 照片版式（实测）

```text
file.place      {"path":"designs/photo-demo/photo-graded.jpg","x":-8.5,"y":-8.5,"width":603.78}
frame.create    {"rect":[-8.5,300,603.78,468],"content":"graphic"}
object.gradient {"kind":"linear",
                 "stops":[{"location":0,"swatch":"Ink","opacity":0},{"location":100,"swatch":"Ink","opacity":100}],
                 "from":[-8.5,300],"to":[-8.5,468],"target":"fill","ids":["<矩形 id>"]}
```

- 渐变方向**必须用 `from`/`to` 显式坐标**；用 `angle` 容易反向，反了会出现一条水平硬边。
- 文字压在照片上时，照片那一侧整体压暗 15–25%，保证对比度。
- 照片像素宽度 ≥ 置入宽度（pt）× 4.1667（300dpi）；不够就回 PhotoCraft 重新裁切重采样。

## 9. 已知坑（都踩过）

1. `frame.create` 的 rect 是角点对，写成 `[x,y,w,h]` 会得到一个怪异尺寸的框。
2. 不选文字就 `type.char`：**静默无效**（返回 `null`，不报错）。
3. 不设中文字体：导出是豆腐块，`font.list` 会显示 `missing`。
4. `fill` 传 hex 会失败；要么先建色板传名字，要么用 `object.color`。
5. `text.selectStory` 需要 `point`（帧坐标内任意点）；`text.select` 需要 `story` + **字节**偏移（中文 1 字 = 3 字节）。
6. `batch` 里引用前一步：`"$0.id"`、`"$2.story"`；字符串里嵌值用 `"${2.id}"`。
7. 导出 PNG 不传 `scale` 时 MCP `export_png` 默认 2×；`render_page` 默认 1×。
8. 出血：底色/底图要覆盖 `[-bleed, -bleed, 页宽+bleed, 页高+bleed]`。
