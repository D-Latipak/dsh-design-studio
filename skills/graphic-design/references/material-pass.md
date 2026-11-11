# 素材关（Material Gate）——先解决「画面从哪来」，再谈排版

**一句话：画面从哪来，由用户的要求和内容决定；素材关要保证"能用、干净、够清楚"，而不是"够多"。**
本文件管取材顺序、素材板、生图执行与位图⇄矢量联动做法。章程 §1.8 是入口；
怎么造见 `assets-generation.md`，去哪取见 `free-assets.md`，怎么修见 `photocraft-pipeline.md`。

> **没有配额。** 要不要位图、要几张、占多大面积，由用户明确要求和 `style-dna.md` 决定。
> 用户要纯文字、纯矢量、线稿、纯色块、全 CSS 渐变——都照做，不需要"例外说明"。
> 本文件里出现的数字（分辨率、尺寸、行数）都是质量口径，不是画面构成规定。

## 一、时机（可以并行，但不是义务）

| 阶段 | 正在发生 | 素材关动作 |
|---|---|---|
| 参考关 1.5 步骤 2（`board.png` 成型） | 参考板落盘 | **如果这单确实需要素材**，可以在等过审时开工：抓素材 / 生图，省时间 |
| 1.5 步骤 3–4（精读 → 交付过审） | 写 `reference-study.md` | 素材候选可以顺手摆出来，也可以等方向定了再取材——**由你判断，不是必做** |
| 1.5 步骤 5（静默时钟） | 等用户回话 | 有活就干，没活不用硬凑 |
| §2 决策单 | 定稿 | 有素材就写编号（「主视觉 M03 / 底纹 M05」）；纯排版稿写「无位图，用户要求」 |
| 三方向门 → 建画布 | 真初稿 | **闸门**：选中素材已落盘、需要处理的已过 PhotoCraft |

**素材板是可选的交付物**：备了就摆给用户看（帮他判断素材方向），没备也不影响参考过审。
**不要为了"五件套齐全"去凑素材**——用户要纯排版，就没有素材板。

## 二、取材顺序（效率顺序；用户指定了来源就照用户，不许拿它覆盖用户的选择）

| # | 来源 | 「合适」的判据 | 动作 | 记账 |
|---|---|---|---|---|
| 1 | 用户素材 | 主题对、够大、有权 | 直接进 PhotoCraft 修整 | 写进 `material-plan.md` 备注 |
| 2 | `designs/assets/` 已有 | 同上，且之前过审过 | 先 `read_image` 复核，别信文件名 | 沿用原 manifest 记录 |
| 3 | **3D 建模再平面化**（图案/插画/图形母题的**首选**） | 需要可控的形状、角度、风格；素材站没有对味的 | `proc-mesh.py` / 图元拼装 / 客户模型 → 出帧 → 位图或 `imageTrace`（见 `3d-to-graphic.md`） | 记进 `material-plan.md`；模型与 `--json` 参数快照一起留档 |
| 4 | 免费素材站（CC0/PD/CC BY） | 许可干净 + 分辨率够 | `Fetch-FreeAsset.ps1`（见 `free-assets.md`） | 脚本自动写 `manifest.json`/`CREDITS.md` |
| 5 | **AI 生图** | 要照片级质感/特定构图，站里没有 | `generate_image` → 落盘 → PhotoCraft | 手写 `sources.md`（提示词/渠道/模型/日期） |
| 6 | 自绘矢量 | 只限艺术字/字形/简单几何/图表 | `draw_shape`/`add_text`/写 SVG | 记进决策单即可 |
| 7 | 占位 | 以上都不行 | 明确做占位版 | 交付说明必须写「本版占位」 |

**第 3 级优先于第 4 级**：素材站下的图如果画质差、风格不对、构图不可控，**回第 3 级自己建模**，不要凑合。

「跳级」的正当事由：上一级**主题对不上 / 分辨率不够 / 许可不干净 / 画风不对**。缺一条才能往下走，
并在 `material-plan.md` 的「备注」里写清为什么跳。
**注意第 3 级不是"兜底"，是首选**：图案类需求可以直接从第 3 级开始，不算跳级。

## 三、画面构成：由用户和内容决定，不设配额

| 情况 | 怎么做 |
|---|---|
| 用户指定了画面类型（要照片/不要照片/要插画/纯文字/纯矢量/线稿） | **照做**。他的指定就是配额。 |
| 用户没说 | 你按用途和内容判断：可以满版照片，可以纯字，可以纯色块，可以一张插画，可以纯图表，可以程序化纹理。 |
| 用户给了素材或参考图 | 优先用他的；不够再补，不许换成你觉得更好的。 |

判断结果写进决策单的「画面来源」一行：每张素材/每个图形元素为什么在这、负责什么。
**不要求"位图面积 ≥ 30%"，不要求"每单至少两张图"，也不要求"必须有材质层"。**
纯矢量稿不是退化稿——只要那是用户要的（logo、图标、纯文字海报、图表、字体即内容的海报都合理）。

质量口径（这些仍然要过）：

- 置入任何位图前，确认它的分辨率撑得住最终尺寸（印刷 300dpi：px = pt × 4.1667；屏幕 ≥ 2×）。
- 照片/生图/纹理进版面前做一次预处理（裁切、重采样、必要的影调与锐化），除非用户要原样。
- 用户要"手作感/粗糙感"，就不要为了"高级"把它磨平；反过来也别把干净素材加噪点当风格。

## 四、产出物（按需给，不凑齐）

**只有一项是强制的：进了位图，就必须有 `material-plan.md` 记账。** 其余按画面需要给。
纯排版稿没有素材表是正常的，不是缺项。

| 产物 | 路径 | 怎么来 |
|---|---|---|
| 素材表 | `designs/<slug>/material-plan.md` | 手写，模板见下 |
| 编号素材板 | `designs/<slug>/materials-board.png` | `New-ContactSheet.ps1`，M01… 编号 |
| 素材与账本 | 素材本体：`designs/<slug>/assets/`；跨项目复用的免费素材库：`designs/assets/`；账本固定 `designs/assets/manifest.json` + `CREDITS.md` | `Fetch-FreeAsset.ps1` 自动维护账本；手工素材补记。**同一条素材只放一处，素材表里写相对项目的路径（如 `assets/m01.jpg`）** |
| AI 出处 | `designs/<slug>/sources.md` | 每条：提示词原文 / 渠道 / 模型 / 尺寸 / 日期 / 文件名 |

**素材表模板**（照抄这份，不要自创字段）：

```markdown
# <slug> 素材表

| 编号 | 用途/位置 | 文件 | 来源 | 许可/署名 | 像素 | PhotoCraft 处理 | 入选 |
|---|---|---|---|---|---|---|---|
| M01 | 满版主视觉 | assets/ai-forest-01.jpg | generate_image / z-image-turbo / 2026-11-06 | AI 生成（无水印） | 1792×1024 | crop→2480×3508 / levels / smartSharpen | ✅ |
| M02 | 底纹 | assets/paper-tile.jpg | Poly Haven / CC0 | 无需署名 | 2048² | 平铺 + levels 压暗 | ✅ |
| M03 | 备选（裁掉） | assets/m03.jpg | Cleveland / CC0 | 记录作者 | 1200² | — | ❌ 构图太满 |
```

**素材板**（编号与素材表一一对应，标签写编号+用途，不写文件名）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skills>\graphic-design\scripts\New-ContactSheet.ps1" `
  -Images "designs\<slug>\assets" -Out "designs\<slug>\materials-board.png" `
  -Title "<slug> 素材板 M01–M08" -Cols 4 -Labels "M01 主视觉|M02 底纹|M03 备选|M04 备用纹理"
```

- 目录模式**按文件名排序**拼板：M 编号必须与排序一致，否则把入选文件改名成 `m01-*.jpg`、`m02-*.png` 再拼。
- `-Labels` 与图数等长；缺省回落文件名。板子只放 6–16 张，别把废弃候选也拼进去。
- 板子出图后必须 `read_image` 自己看一遍：跑题、带假字、带水印、糊的，当场删掉再重拼。

## 五、背景 / 底纹专项（最常被糊弄的一层）

1. **背景单独出图**，不要从主视觉里裁一块放大——构图和留白都对不上。
2. 提示词 **20–60 词**，只写材质 / 色场 / 光线 / 留白，**不写**「海报 / 标题 / 字体 / 日式」这类词
   （本地 Z-Image 会自己长假字，实测见 `assets-generation.md`）。例：
   `abstract washi paper, one soft chartreuse-to-vermilion gradient, risograph grain, empty upper third, no typography, no letters`
3. **按目标比例出图**（`size` 用 1:1 / 16:9 / 3:4 = 版面比例），不要出方图再硬裁成瘦长条。
4. **一次 2–4 变体**（`count` 1–4 或连出两张），拼一张小 contact sheet 一起看，别出一张就用。
5. **构图留空**：写明 text-safe 区（「上 1/3 留空」），文字层不跟画面抢。
6. **对比测试后定**：把主标题色值/字重放上去看可读性（目标正文 ≥4.5:1、大字 ≥3:1）；
   不够就先 PhotoCraft `image.adjustments.levels` 压暗，再不行换变体。
7. **底纹要能平铺**时：PhotoCraft 里 `edit.definePattern` + `layer.newFillLayer.pattern` 铺满整幅后
   `doc_export`，交一张满版位图给版面——**不要指望在矢量里反复复制贴图**（参数先用 `command_list` 查）。

## 六、AI 生图执行细节（只写本机能跑通的）

- 默认渠道「本地 Z-Image (sd.cpp)」`http://127.0.0.1:11436/v1`，模型 `z-image-turbo`；**只使用已配置渠道里的模型**，不编模型名。
- 流程：`generate_image {prompt,size,count,model}` → **落盘**（附件按 `attachment_id` 的 sha256 从
  `%USERPROFILE%\.dsh\attachments\v1\objects\<hex前2位>\<hex>` 复制到 `designs/<slug>/assets/ai-<role>-NN.<ext>`，
  扩展名按 `media_type`）→ `read_image` 查假字/水印/构图 → PhotoCraft → 置入。
- **不落盘就等于没有素材**：附件引用不能进版面，PhotoCraft/VectorCraft 只认文件路径。
- 变体靠 `count` 与 `edit_image`：加元素/换局部（提示词写「保持构图/留白/配色不变，添加 X」）靠谱；
  **整幅换色回 PhotoCraft**（shim 固定 strength 0.6，实测改不动底色）。
- 后台模式（`wait_for_completion:false`）只在并行做别的事时用，之后 `get_image_generation_task` 查一次，不要轮询。
- 单张 20–40s（RTX 4060 Laptop / Q5_0），一次规划 2–4 张；同一时间只跑一个 sd 进程。
- 水印按渠道：本地 Z-Image 无水印；带水印渠道的图**不许抹标识当常规操作**，交付说明写明「AI 生成素材」。
- 每条生成都进 `sources.md`；AI 图是插画素材，不当实拍证据/产品图。

## 七、矢量 ⇄ 位图联动（按画面需要，不设次数）

一次交接要不要做、做几次，取决于画面实际需要：**有照片要进矢量稿就交接一次，有矢量要加质感再交接一次**，
纯字稿可能一次都不需要。做了就要在 `material-plan.md` 或交付说明里点名（走了哪条 R），产物路径写清。
文件之间靠**落盘**交接，不靠剪贴板。下面的 `designs/…` 是相对**设计工作区**的写法；
真正发给 MCP 时一律写绝对路径（读写根按绝对路径校验，见章程铁律 4）。

| # | 链路 | 工具与命令 | 产物 | 验收 |
|---|---|---|---|---|
| **R1** | AI/照片 → 满版底 + 矢量字（位图→矢量） | PhotoCraft `doc_open`→`image.crop`→`image.adjustments.levels`→`filter.sharpen.smartSharpen`→`doc_export`；VectorCraft `file.place`（`rect` 含出血）+ `add_text` | `assets/bg-graded.jpg` → `<slug>.vcraft` | 图 `image.info` 的 effectivePpi ≥300；`doc_inspect` bounds 盖住出血；标题对比达标 |
| **R2** | 矢量主视觉 → 加质感 → 回置（矢量→位图→矢量） | VectorCraft `export {format:"png", path, scale:4.1667}`；PhotoCraft `doc_open`→`filter.gallery.filmGrain`→`image.adjustments.curves`→`doc_export`；VectorCraft `file.place` 回置 | `assets/<slug>-base.png` → `assets/<slug>-textured.jpg` | 回置后 `doc_inspect` 无越界；原矢量层保留（可回退） |
| **R3** | 抠图 → 透明 PNG → 矢量合成（位图→矢量） | PhotoCraft `select.subject`（或 `layer.removeBackground`）→`select.inverse`→`edit.clear`→`doc_export {format:"png"}`；VectorCraft `file.place` 叠加 | `assets/cutout.png`（RGBA） | 边缘无白边/锯齿；`image.info` 有 alpha；主体与底色对比够 |
| **R4** | CC0 纹理 → 平铺/调色 → 满版底（位图→矢量） | PhotoCraft `doc_open`→`image.adjustments.levels`→`edit.definePattern`→`layer.newFillLayer.pattern`→`doc_export`；VectorCraft `file.place` 满版 | `assets/tile-graded.jpg` | 拼接处无接缝；整幅只置一张，不在矢量里重复贴 |
| **R5** | 矢量排版 → 位图化 → 印刷质感（矢量→位图） | VectorCraft `export {format:"png", path, scale:4.1667}`；PhotoCraft `doc_open`→`filter.gallery.grain`→`image.adjustments.curves`→`doc_export` | `assets/<slug>-print.jpg` | 文字边缘不糊（scale≥4.17）；成品图另存，源 `.vcraft` 保留 |
| **R6** | 半调/丝网/阈值 → 回矢量叠加（位图→矢量→位图） | PhotoCraft `image.adjustments.threshold` / `image.adjustments.posterize` / `filter.gallery.halftonePattern` → `doc_export`；VectorCraft `file.place` 灰度图 → `object.vectorHalftone`（或 `imageTrace.make`→`imageTrace.expand`） | `assets/halftone.png` / 矢量网点组 | 网点在 100% 视图下不断线；`doc_inspect` 网点数量合理；印刷稿先核对网点频率（`frequency` 20–300）与印厂要求 |

> R2/R4/R6 里 PhotoCraft 的 `filter.*`、`edit.definePattern`、`layer.newFillLayer.pattern`，以及 VectorCraft 的
> `object.vectorHalftone`/`imageTrace.*` 参数**未逐项实测**：先 `command_list {filter:"…"}`（VectorCraft）或
> PhotoCraft `command_list {filter:"…"}` 看 `params`，小样试一张再上正式稿。

**R1 最小可跑链**（参数按版面换算，下面是 A4 300dpi 的示例值）：

```text
# PhotoCraft（裁切与重采样同步完成；尺寸按版面 300dpi）
doc_open      {"path":"designs/<slug>/assets/ai-forest-01.jpg"}
command_run   {"id":"image.crop","params":{"x":0,"y":120,"width":1792,"height":2528,
               "targetWidth":2480,"targetHeight":3508}}
command_run   {"id":"image.adjustments.levels","params":{"inBlack":8,"gamma":1.04,"inWhite":250}}
command_run   {"id":"filter.sharpen.smartSharpen","params":{"amount":45,"radius":1.1,"reduceNoise":10}}
doc_export    {"path":"designs/<slug>/assets/bg-graded.jpg","format":"jpg","quality":93}

# VectorCraft（rect = [x, y, width, height]，含出血；宽高比按图，fit 保比例）
run_command   {"command":"file.place","params":{"path":"designs/<slug>/assets/bg-graded.jpg",
               "rect":[-8.5,-8.5,612.28,858.89]}}
run_command   {"command":"object.arrange.sendToBack","params":{}}
add_text      {x:56.7, y:430, text:"…", size:96, font:"Noto Serif SC", color:"#F2E8D5"}
```

**R3 最小可跑链**：

```text
doc_open      {"path":"designs/<slug>/assets/product-src.jpg"}
command_run   {"id":"select.subject","params":{}}
command_run   {"id":"select.inverse","params":{}}
command_run   {"id":"edit.clear","params":{}}
doc_export    {"path":"designs/<slug>/assets/cutout.png","format":"png"}
```

两条链跑完都要 `read_image` 看产物再往下；被拒/报错时先看 PhotoCraft `doc_inspect` / VectorCraft `image.info`，不要盲改参数。

## 八、闸门自检（建画布前 + 交付前）

**建画布前**
- [ ] `material-plan.md` 存在，编号连续（M01…），入选的都标了 ✅/❌ 与理由（纯排版稿写「无位图，用户要求」）。
- [ ] 入选素材**已落盘**（是文件，不是附件引用），需要处理的已过 PhotoCraft。
- [ ] `materials-board.png` 已拼、已 `read_image` 自查（无假字/水印/跑题）。
- [ ] 免费素材已进 `manifest.json`；CC BY / CC BY-SA 已进 `CREDITS.md`；AI 素材已进 `sources.md`。

**交付前（进 quality-checklist）**
- [ ] 每张置入图的 effectivePpi 达标（300dpi 印刷 / 2× 屏幕），没有硬放大的糊图。
- [ ] 做过的跨引擎交接已点名，产物路径写进交付说明。
- [ ] 水印/假字/来源不明/参考图入版面的情况：0。

## 九、反模式（命中就退回）

| 反模式 | 为什么错 | 改法 |
|---|---|---|
| 用 `draw_shape` 画照片/写实背景（用户要的写实画面） | 程序感，且这不是矢量的强项 | 回 §二 取材，走 R1；用户明确要"矢量插画"时按矢量做 |
| 纯色块 + 渐变代替用户要的材质 | 用户要材质却没给材质 | 加一张 CC0 纹理或 AI 底纹（R4），或问用户 |
| 一稿全矢量、没有一张位图（用户要照片/材质时） | 没落实用户的要求 | 补主视觉或底纹；用户本来就要纯矢量则无需改动 |
| AI 图不落盘直接塞版面 | 引擎读不到附件，返工 | 按 §六 落盘成文件 |
| 带假字/水印的 AI 图入版面 | 交付事故 | 换更抽象提示词、裁掉、或换图 |
| 把参考图当素材 | 版权 + 参考不进画布（章程 §1.5） | 回素材站/生图重取 |
| 只出一张背景就用、不做对比测试 | 字压不住、返工 | 出 2–4 变体，压字测对比再定 |
| 在矢量里反复复制贴图当底纹 | 文件膨胀、接缝明显 | PhotoCraft 平铺成一张满版图（R4） |

## 十、失败降级（如实上报，不硬凑）

| 情形 | 降级路线 | 必须写进交付说明 |
|---|---|---|
| 素材站连不上/限流 | 换源 → `-AllowAnyLicense` 前先问用户 → AI 生图 → 占位 | 用了哪个源、跳过了什么、风险是什么 |
| 生图服务未起/报错 | 让用户跑 `launch.ps1`（agent 不自启）→ 期间先用素材站/占位 | 「生图不可用，本版 X 为占位/素材站图」 |
| AI 图分辨率不够满版 | 缩小使用面积（当小插图/局部）或改矢量+真实照片 | 分辨率与允许的物理尺寸 |
| 许可判断不了 | 当没有许可，换素材 | 换掉了什么、为什么 |
| 客户必须用带水印/来源不明图 | 拒绝或让用户书面确认 | 风险原文 + 用户确认 |
