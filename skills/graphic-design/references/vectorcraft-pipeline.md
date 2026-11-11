# VectorCraft 出稿配方（产线 A）

VectorCraft 是 Illustrator 级的矢量引擎。**单件成品——海报/封面/社媒图/logo/图标/插画/信息图——在这里合成到成品**（照片/生图用 `file.place` 置入，矢量负责字、形、几何与版式；不要用图元硬画照片或复杂插画），
不是「排版完再转过去」。

两种驱动方式，同一个引擎：

| 方式 | 何时用 | 入口 |
|---|---|---|
| **MCP 工具（默认）** | 边画边看、要改、要选 | `mcp__vectorcraft__*`，33 个工具，headless |
| CLI 批处理 | 一次成型、步骤留档、MCP 没起来时 | `vectorcraft-cli run --commands <步骤.json> --export <out>` |

可执行：`C:\Program Files\ArtCraft\VectorCraft\vectorcraft-cli.exe`
命令目录 966 条（0.23.0；0.18.0 时为 822，只增不减）；`commands` 列全量（每条带 `id` / `label` / `menu` / `params`，按 id 过滤即可），`info <file>` 看文件摘要。
**0.23 起引擎会拒绝命令没声明的键**：多传一个参数名就是硬报错，配方里的参数必须照 `params` 抄，不许自创。
**本 CLI 没有 `describe` 子命令**（实测报 unknown subcommand）；参数看 `commands` 里那一项，或走 MCP 的 `command_list`。

## 〇、素材层先上（素材关在本引擎的落点）

**顺序固定：底纹/背景 → 主视觉 → 纹理/叠加 → 矢量字与形。** 先摆位图，再画矢量，
不要反过来「先排版再找地方塞图」——那会逼着改版式迁就图。
素材从哪来、几张、怎么记账见 `material-pass.md`；这里只讲**落进 VectorCraft 这一侧的动作与验收**。

### 置入命令（`file.place`，参数取自本机 `commands` 注册表）

```text
run_command {"command":"file.place","params":{
  "path":"designs/<slug>/assets/bg-graded.jpg",
  "rect":[-8.5,-8.5,612.28,858.89]     // [x, y, width, height]；fit 保比例
}}
→ {"ids":[…], "name":"bg-graded.jpg", "format":"jpeg", "width":…, "height":…, "warnings":[]}
```

- `rect` 是「装进这个框、保比例」，**不是**拉伸；精确尺寸用 PhotoCraft 先重采样。
- 也可用 `at:[x,y]` 给中心点；`replace:true` 换掉当前选中的对象（改稿用）；`link:true` 保持外链。
- **栅格图按文件自身 100% 物理尺寸进入**（按文件 ppi，缺省 72）——所以文件像素不够时，
  置入后 `image.info` 的 `effectivePpi` 会直接掉下来。**先在 PhotoCraft 按目标尺寸裁切重采样，再置入。**
- 置入后对象**处于选中态**；紧接着 `set_paint` 会把它一并改色（见「五条必守规则」第 1 条）。

### 顺序与层序

| 步 | 放什么 | 命令 | 要点 |
|---|---|---|---|
| 1 | 底纹/背景 | `file.place` → `object.arrange.sendToBack` | `rect` 含出血（A4：`[-8.5,-8.5,612.28,858.89]`） |
| 2 | 主视觉 | `file.place` | 与底纹错开构图；不要两张都满版抢焦点 |
| 3 | 纹理/叠加层 | `file.place` → `object.arrange.bringToFront` | 能先在 PhotoCraft 合成好就合成好，别在矢量里叠多层 |
| 4 | 字与形 | `add_text` / `draw_shape` | 中文显式给字体；一物一色 |

### 验收（三道，缺一不可）

1. `image.info {id}`：`effectivePpi` ≥ 300（印刷）或 ≥ 2× 目标像素（屏幕）；`pixelWidth/Height` 与版面尺寸对得上。
2. `doc_inspect`：图的 `bounds` 盖住出血框、没有越界/缩放异常；层序是「底图在下、字在上」。
3. `links.check {}`：外链图状态 `ok`（`link:true` 时）；嵌入图则 `embedded`。
   `render_preview {max_side:1200}` → `read_image` 看整张，**别拿返回 `bytes` 当验收**。

### 与 PhotoCraft 的往返（两个方向都要能走）

```text
位图 → 矢量：PhotoCraft `doc_export` 成品 jpg/png → VectorCraft `file.place`（R1/R3/R4）
矢量 → 位图：VectorCraft `export {format:"png", path, scale:4.1667}` → PhotoCraft 加质感 → 回置（R2/R5）
R6 半调/丝网：PhotoCraft 先做阈值/半调（位图）→ VectorCraft 置入/描摹成矢量网点 → 需要时再光栅化回位图
```

- 矢量导出 PNG 用 `scale:4.1667`（A4 300dpi）；回置前 `read_image` 看一遍，别让文字被二次压缩糊掉。
- **印刷 PDF 仍由本引擎 `document.exportPdf` 出**（文字保真）；PhotoCraft 回的位图是质感层或社媒版，
  不要拿位图去顶印刷 PDF。
- 每单至少 2 次交接（≥1 位图→矢量、≥1 矢量→位图），在 `material-plan.md` 里点名配方编号。

> `file.place` 的 `rect`/`at`/`replace` 参数来自本机命令注册表，**落版前先跑一张小样**；
> `imageTrace.*`、`object.vectorHalftone` 等未逐项实测，用前 `command_list {filter:"…"}` 查参数。

## 一、MCP 工具（首选）

挂法是 bundle 里的 `vectorcraft-tools`（stdio + `--headless` + 两个 automation root）。可用工具：

| 工具 | 关键参数 | 说明 |
|---|---|---|
| `run_command` | `{command, params}` | 跑任意引擎命令，等价 CLI `--cmd` |
| `command_list` | `{filter, brief, enabled_only}` | 查命令目录（`brief:true` 只回摘要） |
| `command_batch` | `{steps:[{id,params}], atomic}` | 一次多步；`atomic:true` 合成一步撤销 |
| `draw_shape` | `{shape, x, y, width, height, fill, stroke, radius, rotation}` / 多边形星形 `{cx,cy,radius,sides}` / 线 `{x1,y1,x2,y2}` | 画活形状，**自带 paint** |
| `draw_path` | `{points \| d, closed, fill, stroke}` | 贝塞尔路径 / SVG path data |
| `add_text` | `{x, y, text, size, font, color, width, height, fit, justify}` | 点文字（`x,y`=`首行基线`）；给宽高变区域文字 |
| `set_paint` | `{fill, stroke, strokeWidth, ids}` | 改选中（或 `ids`）的 paint，同时改新画默认值 |
| `doc_inspect` | `{kind, ids, depth, limit}` | 画板/图层树/选中/历史 |
| `render_preview` | `{max_side, artboard}` | **直接返回整张 PNG**，就是"看稿" |
| `export` | `{format, path, scale, artboard, outlineText}` | png/jpg/svg/eps/pdf/ai/tif/psd… |
| `save_file` | `{path}` | 存 `.vcraft` / `.ai` / `.svg` |
| 其他 | `transform` / `pathfinder` / `apply_effect` / `create_graph` / `text_wrap` / `undo` / `redo` / `open_file` | |

## 二、已验证的 A4 海报链路（跑通过，出图核对过）

```
run_command {command:"file.new", params:{width:595.28, height:841.89, units:"Points", colorMode:"rgb", bleed:8.5, name:"<slug>"}}
draw_shape  {shape:"rectangle", x:-8.5, y:-8.5, width:612.28, height:858.89, fill:"#0E1B2A"}      // 出血底
draw_shape  {shape:"rectangle", x:56.7, y:500, width:120, height:6, fill:"#E2603C"}                // 强调线
add_text    {x:56.7, y:430, text:"手冲咖啡", size:96, font:"Noto Serif SC", color:"#F2E8D5"}      // y = 基线
add_text    {x:56.7, y:310, text:"SLOW BREW / 开业", size:22, font:"Noto Sans SC", color:"#E2603C"}
add_text    {x:56.7, y:545, text:"10月18日 周六 09:00\n南山区蛇口老街 27 号", size:16, font:"Noto Sans SC", color:"#F2E8D5"}
render_preview {max_side:1200}                                                                     // 看稿
export      {format:"png", path:"…\\<slug>.png", scale:2}
save_file   {path:"…\\<slug>.vcraft"}
```

中文实测正常（Noto Serif SC / Noto Sans SC 本机可用）。

## 三、CLI 批处理（同等能力，步骤留档）

```powershell
& "C:\Program Files\ArtCraft\VectorCraft\vectorcraft-cli.exe" `
  run --in "<可选>" --commands "<步骤.json>" --export "<out.png>" --scale 2
```

步骤文件 UTF-8、JSON 数组、每项 `{"command": id, "params": {…}}`，顺序执行、出错即停；
末尾 `--export` 按扩展名出件。返回每条一行 JSON，`warnings` 必须读。

**坑（实测）**：PowerShell 给原生 exe 传参会吃掉双引号，`--params '{"a":1}'` 直接报
`key must be a string at line 1 column 2`。**CLI 路径一律写 `--commands` 文件**，不要内联 JSON。

## 四、五条必守规则

1. **每件物体自己带颜色。** `draw_shape {…, fill}` / `add_text {…, color}` 一物一色最稳。
   `set_paint`/`paint.setFill` 是**双作用**：改选中对象 + 改新画默认值。而**刚画完的对象还是选中状态**——
   紧接着调一次 `set_paint` 就把它改色了。实测事故：深底画完后一句 `set_paint {fill:"#E2603C"}`
   把整页底刷成橙色、橙色强调线彻底消失。要批量改色就显式传 `ids`，否则一物一色。
2. **`draw_shape` 的 `{x, y}` 是左上角 + 宽高**（与 DesignCraft `frame.create` 的角点对**相反**）；
   出血底图给负坐标、宽高各加 2×出血。多边形/星形用 `cx, cy, radius`，线用 `x1,y1,x2,y2`。
3. **`add_text` 的 `y` 是首行基线**（工具描述原文 "Create point type at (x, y) (the first baseline)"），
   96pt 字的框顶比 y 高 100pt 以上。**别心算顶边**，读返回的 `id` 后用 `doc_inspect {ids:[id]}` 拿 `bounds`。
   要框排：给 `width`/`height` + `fit:"shrinkText"`（缩字防溢出）或 `"autoHeight"`（只长高）；
   区域文字排不下会在返回里带 `overflow`。
4. **中文必须显式给字体**，否则回落。先 `run_command {"command":"text.fontList","params":{"family":"Noto Serif SC"}}` 确认；
   逐字改样式 `text.setStyle {id, start, end, font, size, fill}`，**`start`/`end` 是 UTF-8 字节偏移**（一个中文字 3 字节）。
5. **CMYK 稿用 CMYK 色值**：`{"c":0,"m":8,"y":16,"k":5}`。在 `colorMode:"cmyk"` 文档里填 hex，导 PDF/X 会警告
   `this CMYK document has 1 RGB colour: … dark ones can come out as rich blacks on several plates`——深色印成四色黑。

## 五、出件

| 用途 | 调用 | 备注 |
|---|---|---|
| 预览 PNG | `render_preview {max_side:1200}` | 直接回图，不落盘 |
| 交付 PNG | `export {format:"png", path, scale:2}` | `scale` = 像素/点；A4 300dpi ≈ `4.17` |
| 局部放大 | `export {format:"png", path, rect:[x,y,w,h], scale:3}`（CLI 走 `document.export` 同参） | `rect` 是页面 pt，y 向下 |
| 印刷 PDF | `document.exportPdf {path, standard:"pdfX4", marks:{trim:true,registration:true}, bleed:{useDocument:true}}` | 也支持 `pdfX1a`/`pdfX3`/`pdfA2b`；`advanced:{outlineText:true}` 全转曲 |
| 可编辑源 | `save_file {path:"x.vcraft"}` | 也可 `.ai`（可再编辑的 PDF）、`.pdf`、`.svg` |
| 格式转换 | `vectorcraft-cli convert IN OUT` | SVG/PDF/AI/EPS/PSD/PNG…，参数见 `--help`（未逐项实测） |

## 六、看稿（`Test-Design.ps1` 管不到 `.vcraft`）

`Test-Design.ps1` / `Inspect-Render.ps1` / `New-Revision.ps1` **只认 `.designcraft`**。产线 A 三道人工关，都不可跳：

1. `render_preview` 出图 → `read_image` 看整张。别拿 `{"bytes":…,"warnings":[]}` 当验收。
2. `doc_inspect` 对数字：元素是否越出画板（负坐标/超尺寸）、`overflow` 是否残留、字号/色值是否合决策单、
   CMYK 稿有没有混进 RGB。
3. 局部放大：标题区/信息区/角落各 `export {rect, scale:3}` 一张看——缩略图会漏 1pt 错位和小字糊。

改稿：`Copy-Item` 出 `<slug>-v2.vcraft` 再改，原稿 hash 不变。

## 七、与 DesignCraft 的差异（背串必错）

| 项 | VectorCraft（产线 A） | DesignCraft（产线 C） |
|---|---|---|
| 建物坐标 | `{x, y, width, height}` 左上角 | `rect:[x0,y0,x1,y1]` 角点对 |
| 文字 | `add_text` 一步带字号/字体/颜色 | 建文本帧 → `set_story_text` → `type.char`（需先建选区） |
| 溢出信号 | 返回里的 `overflow` | `inspect_document` 的 overset |
| 驱动 | MCP 工具（或 CLI 步骤文件） | MCP 工具（`batch`/`execute`） |
| 自动 QA | **无**（人工三道） | `Test-Design.ps1` 0 error |
| 出血 | `file.new {bleed}` → PDF `bleed:{useDocument}` | `new_document {bleed}` |

## 八、还没验证 / 缺口

- `object.blend.*`、`envelope`、`mesh`、`pattern`、`symbol`、`variable` 数据驱动、`imageTrace`、
  `webExport`、`svgInteractivity`、`create_graph`：工具/命令都在，**未逐条实测**，用前先 `command_list` 看参数并小样试跑。
- VectorCraft 侧没有参数化模板，也没有自动 QA 脚本和改稿脚本；模板就是第二节那段链路。
- 桌面联调（可选）：`vectorcraft.exe --control 7979` 后用 `vectorcraft-cli mcp --connect 127.0.0.1:7979`，
  可拿到 `ui_inspect` / `ui_screenshot` / `pointer_gesture` 等界面工具。本工作流默认 headless，不依赖桌面窗口。
