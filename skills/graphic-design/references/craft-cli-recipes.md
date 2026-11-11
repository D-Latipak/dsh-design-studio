# 其余 Craft 应用的命令行用法（实测）

设计主链之外，本机还装了 6 个「设计相关但不同品类」的应用。**它们不进 agent 的 MCP 工具表**
（PdfCraft 179 个工具、LightCraft 393 个工具——全挂上会把每次请求的上下文吃光），
而是**在需要时用 `pwsh` 调它们的 CLI**。下面每条命令都在本机跑过。

## 0. 总览（版本：2026-11-09 升级后实测；MCP 工具数为旧版实测，按需用 `commands` 复核）

| 应用 | 版本 | 什么时候用 | CLI 入口 | MCP 工具数 | 文件 roots |
|---|---|---|---|---|---|
| **PdfCraft** | 0.20.0 | **交付/印前**：检查 PDF 可打印性、合并多稿、拆页、旋转、提取文字、渲染预览、OCR、加密 | `pdfcraft-cli` | 179 | 可选 |
| **LightCraft** | 0.20.0 | **照片上游**：相机 RAW 冲图、HDR/全景合成、降噪、导出 | `lightcraft-cli` | 393 | 无此参数 |
| **FigCraft** | 0.17.0 | **界面/图形资产**：做 App/网页视觉、图标套件，导出 PNG/SVG/PDF | `figcraft-cli` | 18 | 可选 |
| **DeckCraft** | 0.17.0 | 演示/提案（把设计做成幻灯片） | `deckcraft-cli` | 25 | 可选 |
| **WordCraft** | 0.17.0 | 长文档/报告排版 | `wordcraft-cli` | 17 | 可选 |
| **EffectCraft** | 0.23.0 | **3D 静帧素材（产线 E，主力）** + 动效成片 | `effectcraft-cli` | 27 | 可选 |

对照主链引擎（命令目录 2026-11-09 实测）：DesignCraft 555 条、PhotoCraft 1000 条、VectorCraft 966 条、EffectCraft 749 条。
**结论**：主链走 MCP；这 6 个走 CLI。PdfCraft 179 + LightCraft 393 若挂 MCP，光工具定义就够把上下文挤爆。
命令目录只增不减（本轮 0.18→0.23 / 0.14→0.19 / 0.17→0.22 均无删除），所以旧配方不会突然失效；
但 **VectorCraft 0.23 起会拒绝命令没声明的键**，自创参数名会直接报错。

**原则**：位图和版式主链仍只走 PhotoCraft / DesignCraft 的 MCP；这 6 个应用靠 CLI 按需调用，
调用前先 `--help` 确认参数（不要猜）。复杂参数一律走「JSON 文件 + `run --script`」，
不要用 PowerShell 拼内联 JSON（引号会被剥掉，实测 `--params '{...}'` 会报 `key must be a string`）。

## 1. PdfCraft —— 交付/印前（实测）

```powershell
$pdf = "$env:LOCALAPPDATA\Programs\ArtCraft\PdfCraft\pdfcraft-cli.exe"

# 文档摘要（页数、尺寸 pt、PDF 版本、输出意图、是否加密/带 JS、PDF/A 声明）
& $pdf info designs\jingmo-shengzhang\jingmo-shengzhang.pdf
# → {"pages":1,"first_page_pt":[612.28,858.89],"pdf_version":"1.6","output_intents":["FOGRA39"],"producer":"DesignCraft",…}

# 印前自检（可打印性/结构问题；多个文件或目录都行）
& $pdf check designs\jingmo-shengzhang\jingmo-shengzhang.pdf --timeout 20
# → checked 1 files: {"ok": 1}   （有问题会列出，退出码非 0）

# 指定页渲染成图（给客户看 / 快速核对）
& $pdf render designs\jingmo-shengzhang\jingmo-shengzhang.pdf --page 1 --dpi 96 --out designs\assets\pdfcraft-render.png
# → rendered page 1 at 96 dpi: 817×1146 px

# 抽文字（核对文案、查是否有可选中文本）
& $pdf text designs\jingmo-shengzhang\jingmo-shengzhang.pdf --page 1

# 合并 / 提取 / 拆分 / 顺序编辑
& $pdf combine a.pdf b.pdf --out combined.pdf
& $pdf extract in.pdf --pages 1,3,5-8 --out picked.pdf
& $pdf split in.pdf --every 2 --out-dir designs\out
& $pdf edit in.pdf --out fixed.pdf --rotate 1,3:90 --delete 2,4 --move 5:1 --title "…"

# 假涂黑检查（把文字盖住但没删掉 = 泄密风险）
& $pdf audit in.pdf
# 批量：转图/OCR/优化
& $pdf batch designs\out --steps convert,ocr,optimize --out-dir designs\out2
```

规矩：
- 成品印刷 PDF 先用 DesignCraft 的 `file.exportPdf {standard:"x4"}` 出，再用 `pdfcraft check` 复核；
  DesignCraft 的 `validate-pdf` 与 PdfCraft 的 `check` 是两个独立视角，两个都过再交。
- 客户/印厂给的 PDF：先 `info` + `render` 看一眼，再 `text` 确认文字是否可选中（扫描件要走 `batch --steps ocr`）。
- **不要把 179 个 PdfCraft MCP 工具挂进 agent**；需要时按上面的 CLI 调。

## 2. LightCraft —— RAW / 照片上游（实测）

```powershell
$light = "$env:LOCALAPPDATA\Programs\ArtCraft\LightCraft\lightcraft-cli.exe"

# 直接渲染一张照片（含 RAW）到 PNG/JPG
& $light render "designs\assets\_raw\IMG_0001.CR3" -o "designs\assets\develop\IMG_0001.png"

# 导入照片库 + 按条件查 / 选
& $light run --import "designs\assets\_raw"
& $light commands            # 393 个 MCP 工具对应的命令目录
& $light controls            # 可调的 develop 参数
```

- 照片**逐张精修**仍走 PhotoCraft 的 MCP（裁/调/合成/导出），LightCraft 负责「RAW → 可用图」这一步。
- `merge hdr|panorama|hdr-panorama` 用于多张合成；`denoise-serve` 起降噪服务。
- 没装相机 RAW 素材时不必用它；普通 JPG/PNG 直接进 PhotoCraft。

## 3. FigCraft —— 界面/图形资产（实测）

```powershell
$fig = "$env:LOCALAPPDATA\Programs\ArtCraft\FigCraft\figcraft-cli.exe"

& $fig info "designs\assets\ui.figcraft"                        # 文件摘要
& $fig render "designs\assets\ui.figcraft" -o out.png --scale 2  # 渲染成 PNG
& $fig export "designs\assets\ui.figcraft" -o designs\assets\ui-out --format png   # 逐画板导出
& $fig export "designs\assets\ui.figcraft" -o designs\assets\ui.svg --format svg   # 导出 SVG → 可进版面
& $fig convert "x.fig" "x.figcraft"
& $fig run script.json --in x.figcraft --out y.figcraft
```

- 用途：做 App/网页界面、图标套件，`--format svg` 导出后能直接 `file.place` 进 DesignCraft。
- MCP 只有 18 个工具，但仍是另一个品类，默认不挂；要挂见第 5 节。
- 支持 `--cmyk`、`--bleed`、`--crop-marks`（印刷稿可直接出 PDF）。

## 4. DeckCraft —— 演示/提案（实测 0.12.0）

```powershell
$deck = "$env:LOCALAPPDATA\Programs\ArtCraft\DeckCraft\deckcraft-cli.exe"

& $deck info designs\deck\proposal.deckcraft                 # 幻灯片/版式/主题 JSON
& $deck render designs\deck\proposal.deckcraft --out designs\deck\png   # 每页渲染成 PNG
& $deck convert designs\deck\proposal.deckcraft designs\deck\proposal.pptx
& $deck commands                                             # run 能用的命令
& $deck describe slide.new                                   # 单个命令的参数
& $deck run --cmd 'slide.new={"title":"Q3 results"}' --save designs\deck\proposal.deckcraft
```

- 用途：把设计方案做成对客户的提案幻灯片；每页 `render` 成 PNG 后可当版面素材。
- 版式/主题在 `.deckcraft` 里；改文字用 `run --cmd`，改版式用 `commands` 查命令。

## 5. WordCraft —— 长文档/报告（实测 0.12.0）

```powershell
$word = "$env:LOCALAPPDATA\Programs\ArtCraft\WordCraft\wordcraft-cli.exe"

& $word info designs\doc\report.docx                         # 页数/字数/段落/属性
& $word text designs\doc\report.docx                         # 纯文本
& $word render designs\doc\report.docx designs\doc\page1.png --page 1 --scale 2
& $word convert designs\doc\report.docx designs\doc\report.pdf
& $word run --script designs\doc\steps.json                  # 批量命令脚本（JSON）
```

- 用途：设计说明/交付文档/报告；`convert` 支持 docx/pdf/odt/rtf/html/md/tex/txt/png。
- 只做「文档排版」，不做平面设计；海报/封面仍归 DesignCraft。

## 6. EffectCraft —— 3D 静帧素材 / 动效（实测 0.23.0，749 条命令）

```powershell
$fx = "$env:LOCALAPPDATA\Programs\ArtCraft\EffectCraft\effectcraft-cli.exe"

& $fx --version                                              # 0.23.0
& $fx info designs\3d\poster.ecproj                          # 工程 + 引擎摘要
& $fx commands --filter 3d                                   # 引擎命令目录
& $fx run --args-file designs\3d\cmds.txt --empty --save-as designs\3d\poster.ecproj --json
& $fx render-frame --project designs\3d\poster.ecproj --comp hero --frame 0 --transparent --out designs\3d\hero.png
& $fx render --comp main --out designs\motion\poster.mp4 --format h264          # 要成片时
```

- **两个用途，别混**：
  1. **3D 静帧素材（产线 E，主力）**——产品/包装 mockup、等距结构、立体字。出透明 PNG 进 PhotoCraft 调色，
     再 `file.place` 进 VectorCraft/DesignCraft。完整配方见 `effectcraft-3d.md`。
  2. **动效/短视频版本**——用户明确要「动起来的版本」时才做；`render-frame` 出单帧回流版面，
     `render` 出 mp4/gif/png 序列。
- **不要用内联 `--params '{"…"}'`**：PowerShell 会吞引号，exe 收到 `{a:1}` 直接报
  `params are not valid JSON`。一律 `run --args-file`（一行一个参数，UTF-8 **无 BOM**）。
- **`--transparent` 的前提是 comp 没设 `background`**，否则出 24 位不透明 PNG。
- 平面设计主链不依赖它的动效能力；但**3D 静帧已经进主链**（产线 E），判据见 `effectcraft-3d.md` 第一节。

## 7. 想给 agent 挂更多引擎时

在 `design-studio/cordis.patch.yml` 的 preset `plugins` 末尾按需加行，然后 `remove_bundle` → `install_bundle`：

```yaml
          - id: figcraft-tools
            name: '@deepseek-ai/dsh-mcp-client'
            config:
              serverName: figcraft
              transport: stdio
              command: 'C:\Program Files\ArtCraft\FigCraft\figcraft-cli.exe'
              args: ['mcp']
              toolCallTimeoutMs: 180000
              failOnStartupError: false
```

**不要同时挂 PdfCraft（179 工具）或 LightCraft（393 工具）**——单个会话的工具定义会涨到几万 token，
反而降低设计质量。它们的活交给 CLI。
