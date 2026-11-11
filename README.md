# 平面设计工坊 · Design Studio (DSH agent bundle)

给 DeepSeek Harness（DSH）加一个**会真的做图**的平面设计师 agent：你在聊天框里用一句自然语言下单，
它用一整套 ArtCraft 引擎把设计**做出来**——素材按你的要求取（你的素材 / 素材站 CC0-CC BY / AI 生图 / 自绘 SVG），
照片用 **PhotoCraft** 处理，版式用 **DesignCraft** 排，单件成品在 **VectorCraft** 里合成，
交付前用 **PdfCraft** 做印前检查，最终交付可编辑的源文件（`.vcraft` / `.designcraft` / `.pcraft`）+ PNG/PDF。

**v3.1 的一条变化（2026-11-10）：**

**3D 升级为"图案的第一来源"。** 需要图案 / 插画 / 图标型母题 / 装饰元素时，默认**先建模再平面化**，
而不是手绘矢量：建几何 → 压平光（高 Ambient、去高光，否则出渲染味）→ `render-frame --transparent`
→ 位图直接用，或 `imageTrace.makeAndExpand` 转成可编辑路径。
同时**素材站降为"能用才用"**：下载的图如果画质差、风格不对、构图不可控，回 3D 自己搭，不要凑合。
配方见 `skills/graphic-design/references/3d-to-graphic.md`。
实测：1400px 出帧 → 3 色 trace = 4 条路径 / 93 锚点 / 4 KB SVG，一次调用。

**v3.0 的四条变化（2026-11-10，晚于 v2.0）：**

1. **EffectCraft 从"建模器"改判为"虚拟摄影棚"。** 实测它的 3D 只有六个图元、材质只有标量，
   **没有任何贴图/法线/凹凸/置换通道** —— 所以球只能是球（上一版用 `radius=1500` 的球当橘子就是这个后果）。
   现在：几何只能来自 **客户模型 / 程序化网格（`scripts/proc-mesh.py` → `.glb`）/ AI 生图**，
   图元只用于规则几何体；有机物用图元顶替 = 交付失败。
2. **"形"与"质"一起从模型文件进来。** 五项实测（OBJ+MTL / glTF albedo / normal map / GLB / metallicRoughness）
   全部 PASS：PBR 贴图能完整穿过 `layer.newModel`。推荐自包含 `.glb`，一次调用，无路径解析。
3. **章程从 36 KB / 660 行压到 10 KB / 250 行。** 删掉的是同一批规则在四个小节的重复，
   新增的是**迭代经济**（看局部不看 4K 全图、一次改动只渲一次、能脚本化的自检不靠眼睛）
   与**验收七条**（其中"主体检查"专门拦"用几何体假装有机物"）。
4. **参考精读从 11 字段降到 7 条**，并把 `reference-gate.md` 定为唯一事实源；
   `SKILL.md` 的 19 行等权链接换成 28 行"你在做什么 → 读哪个 → **读多少**"的路由表
   （‡ 只查表 / † 命中才读），把单稿参考阅读量从 ~30 万 token 压到 2–4 万。

**v2.0 的三条根本变化（2026-11-10）：**

1. **用户的要求是唯一权威。** 每一条明确要求（包括"不要什么"）逐字写进 `designs/<slug>/brief-lock.md`，
   编号 R01…，交付时逐条给证据。任何内部规则、模板、清单，与用户冲突时一律让路，并写进交付说明。
2. **风格只能查出来，不能选出来。** 删掉了内置风格图鉴（22 风格 DNA）、审美评分表、"平庸信号"、
   反 AI 味清单。风格一律按用户原话当场联网搜：**范围是全球互联网，来源不限**——设计站、社交平台、
   品牌官网、档案馆、旧物照片、影视截图、展览现场都能当参考；**参考不需要版权**（它不进成品）。
   → 逐张精读 → 写成可溯源（`R0N` / `#NN`）的 `style-dna.md` → 交你过审后才动手。
3. **不做风格裁判。** 没有色数上限、留白配额、"必须一处大胆动作"、位图面积 ≥30%、每单 ≥2 次交接、
   "避开最近 5 单"这类规定。画面构成（要不要照片、几张图、纯字还是纯矢量）由你的要求决定。
4. **矢量图形是"生成"出来的，不是"手绘"出来的。** 需要矢量时优先：3D 渲染（EffectCraft → `imageTrace` 转路径）
   → 程序化 SVG / 参数化几何（脚本算坐标）→ 引擎生成类命令（halftone / trace / pattern / 变形）。
   模型用 `draw_shape`/`path.create` 逐个锚点手搓复杂插画必然歪抖——手写只留给矩形、圆、线、箭头这类简单几何。

**你太久不回复，它按静默时钟自动继续**，不会把等待变成死锁。

> 本文件下半部分（"设计水平 v1.1"、变更表、已知不足）是**沿革记录**：
> 其中提到的风格图鉴、评分表、配额等已被 v2.0 删除或改写，以 `agents/design-studio/design-studio.md` 为准。


```
你：做一张 1080 方图，主题「墨山」，用 AI 生成山峦插画当底，配一枚你画的 SVG 印章
它：generate_image 生图 → 落盘 → PhotoCraft 裁掉水印角 + 调色 → 写 seal-mark.svg
    → DesignCraft 排版（图片满版 + 渐变压暗 + 文字 + 置入 SVG）→ 渲染 → 自己看一眼 → 交付
```

---

## 一、它包含什么

| 层 | 内容 |
|---|---|
| 安装的软件 | **9 个设计相关应用**（MSI 静默按用户安装）：DesignCraft 0.19.0（排版）、PhotoCraft 0.22.0（位图）、VectorCraft 0.23.0（矢量）、PdfCraft 0.20.0（PDF/印前）、LightCraft 0.20.0（RAW/照片库）、FigCraft 0.17.0（界面/图形）、DeckCraft 0.17.0（演示）、WordCraft 0.17.0（文档）、EffectCraft 0.23.0（**3D 静帧素材** + 动效）。**2026-11-10 已全套升级**，命令目录只增不减 |
| DSH bundle | `@local/dsh-design-studio`（本目录），安装进 `desktop` profile |
| Agent preset | `design-studio`「平面设计工坊」——独立人设 + 工具集 + 技能 |
| MCP 连接 | 五条 stdio 连接：`designcraft-cli mcp`（26 排版工具 / 555 命令）、`photocraft-cli mcp --automation-read-root … --automation-write-root …`（26 位图工具 / 1000 命令）、`vectorcraft-cli mcp --headless --automation-read-root … --automation-write-root …`（33 工具 / 966 命令）、`effectcraft-cli mcp --autosave --automation-read-root … --automation-write-root …`（27 个 3D 工具 / 761 命令）、**自建 `mcp/reference-mcp.mjs`**（参考图抓取三工具）。其余 5 个应用**不挂 MCP**（PdfCraft 实测 200 / LightCraft 406 个工具会吃光上下文；FigCraft 19 / DeckCraft 25 / WordCraft 18 按需可挂），需要时用 CLI |
| 素材生成 | **素材站 / AI 生图优先**，**写 SVG** 只做精确图形与字形：本地部署 Z-Image（sd.cpp）。拓扑 **插件 → `127.0.0.1:11436`（`img_shim.py` 转接层）→ `127.0.0.1:11435`（sd-server）**；离线、无水印、约 20–40s/张；**文生图 + 图生图都可用**（图生图走 shim 的 `init_image`，擅长加元素/局部改，整幅换色不可靠）。生图 → 落盘 → PhotoCraft 加工 → DesignCraft 置入 |
| 技能 | `graphic-design`：**需求锁（brief-lock，逐条不偏离）/ 风格研究（按用户原话当场联网爬库 → 精读 → DNA → 过审）/ 参考关（数量门槛 + 静默时钟）/ 素材关（取材顺序 + 素材板 + 背景生图 + 联动配方 R1–R6，无配额）/ 找参考 / 艺术字体与字形设计** + 版式/字体/配色（工具书，非标准）+ DesignCraft 命令配方 + PhotoCraft 流水线 + 免费素材源 + **自造素材（SVG/AI）** + 其余应用 CLI 配方 + 交付检查清单（含需求逐条核对） |
| 素材脚本 | `skills/graphic-design/scripts/`：`New-ReferenceBoard.ps1`（参考板：检索+下载+拼版 + 编号标签）、`New-ContactSheet.ps1`（拼版图）、`Fetch-FreeAsset.ps1`（开放素材源）、`Rasterize-Svg.ps1`（SVG→透明 PNG）、`Install-UserFont.ps1`（字体用户级安装）、`New-Revision.ps1`（改稿版本化） |
| 参考图 MCP | `mcp/reference-mcp.mjs`（零依赖 Node）：`reference_search`（Bing 图搜 + 四站 + 任意直链 → 下载/质检/去重/拼版）、`reference_library`（共享参考库查询）、`reference_status`（来源连通性自检）；索引与缓存落在 `designs/references/.reference-index.json` |
| 章程 | `agents/design-studio/design-studio.md`：工作流（**需求锁 → 风格研究（联网）→ 过审 → 素材按需 → 决策单 → 建画布 → 看稿 → 需求核对 → 交付**）、26 条铁律（只留技术/法律/权威关系）、不偏离原则、升级条件 |

**画面来源听用户的**：用户素材 / `designs/assets/` → 免费素材站（CC0/PD/CC BY）→ AI 生图 → 自绘矢量 → 占位
只是"用户没说时的效率顺序"。用户指定了画面类型（要照片/不要照片/纯字/纯矢量/线稿），就按他的来。
**没有张数分档、没有位图面积下限、没有"每单 2 次交接"**；要不要位图、几次交接，由画面实际需要决定。

**引擎各管一段**（agent 被明确要求不许串台）：

| 引擎 | 管什么 | agent 怎么用 |
|---|---|---|
| **DesignCraft** | 版式与文字：画布/出血、文本帧与样式、图片置入、PDF/X-4 导出 | `mcp__designcraft__*`（555 条排版命令） |
| **PhotoCraft** | 照片/位图：裁切、重采样、调色、锐化、图层合成、去背景、导出 | `mcp__photocraft__*`（1000 条位图命令） |
| **AI 生图** | 插画/氛围/概念图（模型渲染） | `generate_image` / `edit_image`（DSH 生图插件） |
| **自写 SVG** | 印章/图标/纹样/几何主视觉（矢量=代码） | `write` 工具写 `.svg` → `file.place` |
| **VectorCraft** | 单件成品合成：置入素材/生图 + 排版 + 艺术字/字形/几何 | `mcp__vectorcraft__*`（966 条命令，见 `references/vectorcraft-pipeline.md`） |
| **EffectCraft（产线 E）** | **3D 静帧素材**：产品/包装 mockup、等距结构、立体字、客户 glTF/OBJ/STL 模型 → 透明 PNG | `mcp__effectcraft__*`（27 个工具 / 761 条命令；见 `references/effectcraft-3d.md`） |
| **PdfCraft** | 交付/印前：检查可打印性、合并/拆分/旋转、OCR、渲染预览 | `pdfcraft-cli`（CLI，见 `references/craft-cli-recipes.md`） |
| **LightCraft / FigCraft / DeckCraft / WordCraft** | RAW 冲图 / 界面资产 / 演示 / 文档 | CLI 按需调用，同上 |

### 设计水平是怎么来的（v2.0 改写）

v1.1 曾把"设计水平"做成三件内置能力：风格图鉴（22 个风格 DNA）、100 分评分表、18 条"平庸信号"。
**v2.0 把这三样删掉了**——它们让不同需求最后都收敛到同一套"安全做法"，而且会覆盖用户的原话。
现在的做法是：**能力来自用户 + 当场调研 + 手艺**，不是来自内部分数线。

| 能力 | 文件 | 它现在做什么 |
|---|---|---|
| **需求锁定** | 章程 §1 + `designs/<slug>/brief-lock.md` | 用户的每条要求逐字入档、编号，交付时逐条给证据；否定型要求同样核对 |
| **风格研究** | `references/style-research.md` + `scripts/New-ReferenceBoard.ps1` | 用用户原话造检索式 → 当场联网抓真实设计（Are.na / Design Reviewed / Fonts In Use / It's Nice That / 用户给的页面）→ 7 条精读 → 可溯源 DNA（`R0N` / `#NN`）→ 过审 |
| **参考能力** | `references/reference-gate.md` + `references/reference-hunting.md` | 硬下限 ≥4 张、≥3 张专业源、≥2 来源/检索词；参考只进判断、不进画布；联网失败重试 3 轮并上报 |
| **艺术字体** | `references/lettering-and-display-type.md` | 四种字形路线、七种手法、字体许可、静默失败点 |
| **手艺与 QA** | `Test-Design.ps1` / `Inspect-Render.ps1` / `quality-checklist.md` | 只查硬伤与"要求有没有落实"，**不评判风格** |

**没有的门槛**：没有色数上限、留白比例、"一处大胆动作"、评分 ≥70、平庸信号清单、位图配额、交接次数下限、
"避开最近 5 单"。要不要这些，由用户说了算。

> 参考与素材严格分开：参考图存 `designs/references/<slug>/`（研究用，永不进成品），
> 素材存 `designs/assets/`（必须 CC0/PD/CC BY 等可商用许可 + `manifest.json` + `CREDITS.md`）。

---

## 二、怎么用（三步）

1. **新建会话**，在预设（preset）里选 **「平面设计工坊」**。
2. 直接用自然语言下单，例如：
   - `做一张 A4 展览海报：主题「静默生长」，秋季特展，高级极简风，深蓝底 + 米色字，信息：2026.09.12–11.30 / 西岸美术馆 B1`
   - `做一张 1080 方图，主题「墨山」，用 AI 生成山峦插画当底，再画一枚印章放右上角`
   - `没有素材的话自己去网上找可商用的免费图，做一张 A4 展览海报：主题「浪的形状」`（它会去 Met / Commons / Openverse 抓 CC0/CC BY 素材，装 OFL 字体，把素材来源与许可证写进 CREDITS）
   - `把这张照片裁成 1080×1080 方图，调暖一点，压暗四角，再给我一张 A4 版`
   - `这个 PDF 印厂说有问题，帮我查一下能不能打；顺便把第 1 页和第 3 页抽出来`
   - `帮我做张 1080×1080 的小红书封面，咖啡店新店开张，暖色调，首杯半价`
   - `这张图的标题再大 20%，留白不够，重排一版`
3. 它会交付到 `designs/<slug>/`：`.designcraft`（可编辑源文件）+ `.png` 预览（+ 印刷时 `.pdf`），
   并在回复里给设计说明和可改方向。双击 `.designcraft` 用 DesignCraft 打开继续改；照片中间产物在 `designs/<slug>/` 里另存。

> 想微调：直接说人话（「标题换宋体」「橙色换砖红」「照片再压暗一点」）。照片改动它会回 PhotoCraft 重做，再回版面。
> **改稿不会覆盖你的原文件**：它会先在同一项目文件夹里另存 `<名字>-v2.designcraft`，只改副本、只导出 `-v2.png`/`-v2.pdf`，
> 并把这一版改了什么记进 `REVISIONS.md`（收尾用 sha256 核对原稿没被动过）。

---

## 三、产物与目录

```
designs/
├─ free-asset-demo/            示例：从互联网抓 CC0 素材 + OFL 字体做成的 A4 展览海报（含改稿版本）
│  ├─ free-asset-demo.designcraft         v1 初稿（原稿，永远不动）
│  ├─ free-asset-demo.png / .pdf          1191×1684 / PDF-X-4，validate-pdf → valid: true
│  ├─ free-asset-demo-v2.designcraft      v2 改稿副本（标题 150→140pt、信息字号 +0.5pt）
│  ├─ free-asset-demo-v2.png / .pdf       v2 的渲染件
│  ├─ REVISIONS.md                        改稿记录 + 封版核对（各版 sha256）
│  ├─ source-wave.jpg / wave-print.jpg    原图与 PhotoCraft 处理后的图
│  └─ manifest.json / CREDITS.md          素材账本与署名页
├─ local-demo/                  示例：A4 横版海报（**本地 Z-Image 生图** → PhotoCraft 打印级处理 → DesignCraft 排版）
│  ├─ moshan-wide.designcraft
│  ├─ moshan-wide.png           1191×1684
│  ├─ moshan-wide.pdf           PDF/X-4，validate-pdf → valid: true；PdfCraft check → ok
│  ├─ photo-wide.jpg            2480×1750 打印级处理结果
│  └─ sources.md                AI 生成声明（本地渠道/模型/提示词/无水印）
├─ moshan-social/              示例：1080×1080 社媒海报（云端 AI 生图 + 自写 SVG 印章 + PhotoCraft + DesignCraft）
│  ├─ moshan-social.designcraft
│  ├─ moshan-social.png        2160×2160（2×）
│  └─ ai-mountains-square.jpg  AI 图经 PhotoCraft 裁水印角 + 调色后的成品
├─ shan-jian-ri-luo/           示例：A4 影展海报（PhotoCraft 调色照片 + DesignCraft 排版）
│  ├─ shan-jian-ri-luo.designcraft
│  ├─ shan-jian-ri-luo.png     1191×1684
│  └─ shan-jian-ri-luo.pdf     695 KB，PDF/X-4，validate-pdf → valid: true
├─ jingmo-shengzhang/          示例：纯文字 A4 海报（CMYK、出血 3mm、PDF/X-4 通过）
├─ kiln-coffee-social/         示例：1080×1080 社媒方图
├─ photo-demo/                 PhotoCraft 产物：调色大图 + 1080 方图裁切
└─ assets/                     素材库：mountain-dusk.png（测试照片）、ai-ink-mountains.jpg（AI 原图）、
                               seal-mark.svg（自写 SVG 印章）、png/seal-mark.png（光栅化版）、以及另一个
                               会话产出的 _fonts/、_scout/（公版素材与字体）、manifest.json/CREDITS.md

design-studio/                 ← 本 bundle（agent 定义、技能、章程、图标、locale）
scripts/mcp.mjs                ← 独立调试工具：对任一 craft CLI 的 MCP 发单条/批量调用
scripts/pc-grade.json          ← PhotoCraft 调色流水线（MCP 会话脚本）
scripts/poster-photo.dcs       ← 影展海报的 DesignCraft 脚本版（可复现）
scripts/poster.dcs             ← 纯文字海报的 DesignCraft 脚本版
```

---

## 四、架构（它到底怎么跑起来）

```
DSH session（preset: design-studio）
   ├─ persona       → 章程 agents/design-studio/design-studio.md
   ├─ skill-filesystem → 技能 skills/graphic-design/SKILL.md + 8 个 references + 4 个脚本
   ├─ tool-fs / tool-fs-search / tool-pwsh / tool-todo / tool-skill
   ├─ generate_image / edit_image   ← DSH 生图插件（AI 模型渲染）
   ├─ @deepseek-ai/dsh-mcp-client (stdio) ── photocraft-cli.exe mcp   ← 位图引擎（26 工具 / 1000 命令）
   ├─ @deepseek-ai/dsh-mcp-client (stdio) ── designcraft-cli.exe mcp  ← 排版引擎（26 工具 / 555 命令）
   ├─ @deepseek-ai/dsh-mcp-client (stdio) ── vectorcraft-cli.exe mcp   ← 矢量合成（33 工具 / 966 命令）
   ├─ @deepseek-ai/dsh-mcp-client (stdio) ── effectcraft-cli.exe mcp   ← 3D 静帧素材（产线 E，27 工具 / 761 命令）
   └─ @deepseek-ai/dsh-mcp-client (stdio) ── reference-mcp.mjs         ← 参考图抓取（自建，3 工具）
```

- 全部本地：引擎都在你自己机器上跑，不出网、不上传设计稿；只有 AI 生图会把提示词/参考图发到你配置的 API。
- 引擎走 stdio + headless：不需要先开 GUI；生成完再用 GUI 打开源文件。
- 交接物是文件路径：AI 图/照片 → PhotoCraft（jpg/png）→ DesignCraft `file.place`；SVG 直接 `file.place`。
**设计能力强化（A / B / C）**——从「能出稿」到「稳定出好稿」：

| 层 | 是什么 | 怎么用 |
|---|---|---|
| **A. 设计系统 + 模板库** | `skills/graphic-design/templates/`：3 个参数化模板（A4 照片海报 / 1080 社媒方图 / 90×54 名片）+ 6 套色板（hex + CMYK）+ 字号/间距 token + 构建器 | `node templates/build.mjs --list` → 写 values.json → `--template … --values … --run` → 直接出 `.designcraft/.png/.pdf` |
| **B. 自动设计 QA** | `scripts/Test-Design.ps1`：overset、越界、空帧、文本帧重叠、对比不足（2× 渲染 + 亮度 p1–p99）、色板/元素过多 | `powershell -File Test-Design.ps1 -Design <file>`，**0 error 才算过**，交付前必跑 |
| **C. 局部复核渲染** | `scripts/Inspect-Render.ps1`：2× 渲染切 `top/mid/bottom` 局部图 + 缩略全图，`-Compare` 出并排对比 | `powershell -File Inspect-Render.ps1 -Design <file> [-Compare <file>]` → 逐张 `read_image` |

设计 agent 的流程因此变成：**查模板 → 填槽位出稿 → 自动 QA → 局部图复核 → 改一轮 → 交付**。

- PhotoCraft 的文件访问被 roots 限定在设计工作区内（见第五节），这是它的安全边界，不是故障。
- 另外 5 个应用（PdfCraft/LightCraft/FigCraft/DeckCraft/WordCraft）由 agent 用 `pwsh` 调 CLI 完成
  交付检查、RAW 冲图、界面资产、演示/文档/动效等任务（配方见 `references/craft-cli-recipes.md`）。

---

## 五、定制

**换 CLI 路径**（装到别处 / portable zip）：改 `cordis.patch.yml` 里对应的 `command:`，然后
`remove_bundle` → `install_bundle` 重装（本 bundle 是链接安装，改完需要重装一次 patch 才生效）。默认位置：

- `C:\Program Files\ArtCraft\DesignCraft\designcraft-cli.exe`
- `C:\Program Files\ArtCraft\PhotoCraft\photocraft-cli.exe`

**PhotoCraft 的读写边界**：`args` 里的
`--automation-read-root <目录>` / `--automation-write-root <目录>` 决定它能读/写哪些文件，
目录必须已存在，当前放行整个设计工作区 `C:\design-workspace`。
换工作区/想更严（例如只放行 `designs`）：改这两个值后重装 bundle。

**其余 5 个应用默认不挂 MCP**：PdfCraft 实测 200 个工具、LightCraft 406 个，全挂进 agent 会让每次请求
多出几万 token 的工具定义，反而降低设计质量。所以它们通过 `pwsh` 调 CLI 按需使用
（配方见 `skills/graphic-design/references/craft-cli-recipes.md`）。
如果某个应用你会高频用（例如 FigCraft 做 UI），可以单独挂它——MCP 行模板见该文档第 7 节。

**让 agent 也能画矢量图**：在 preset 的 `plugins` 末尾加一段（VectorCraft CLI 已装好）：

```yaml
          - id: vectorcraft-tools
            name: '@deepseek-ai/dsh-mcp-client'
            config:
              serverName: vectorcraft
              transport: stdio
              command: 'C:\Program Files\ArtCraft\VectorCraft\vectorcraft-cli.exe'
              args: ['mcp', '--headless']
              toolCallTimeoutMs: 180000
              failOnStartupError: false
```

**改成驱动已打开的窗口**（实时看到 agent 在你的窗口里操作）：启动 `designcraft.exe --control 7979`，
把对应 `args` 改成 `['mcp', '--connect', '7979']`。注意 connected 模式不支持 roots。
PhotoCraft 对应的是 `photocraft --control <port>` + `photocraft-cli mcp --bridge 127.0.0.1:<port>`。

**改设计口味**：编辑 `skills/graphic-design/references/layout-and-type.md`（色板/字号阶梯/版式配方）。
**改位图流程**：编辑 `references/photocraft-pipeline.md`（命令 id 与参数都是实测过的）。改完新会话生效。

---

## 六、哪些已验证 / 哪些没验证

**已实际验证**
- 9 个应用 MSI 安装成功、SHA-256 与各自官方 `SHA256SUMS.txt` 逐一比对全部 MATCH；版本与工具数见本节末尾条目。
- `designcraft-cli mcp`：握手成功，26 工具；排版全链路（新建→排版→导出）通过。
- `photocraft-cli mcp`：握手成功，26 工具；位图全链路（打开→裁切重采样→levels/vibrance→smartSharpen→导出）通过。
- **DSH 的 MCP 桥**（两条都验证过）：用与 preset 完全相同的命令串把引擎挂到 DSH 后，agent 侧确实拿到工具并实际完成：
  ① 两份排版设计（含 PDF/X-4 `valid: true`）；② 照片调色 + 1080×1080 方图裁切导出。
- 照片→版面交接：`file.place` + `object.gradient`（显式 `from`/`to`）实现照片与底色无缝过渡，实测无硬边。
- bundle 安装后 `include:preset-design-studio` 行 `enabled: true, fiberPhase: active`；profile `bundles` 含 `@local/dsh-design-studio`。
- 中文字体、CMYK 色板、PDF/X-4、出血、渲染-读图-改稿循环都跑通（坑已写进技能文档）。
- **免费素材链路**（2026-10-30）：五个源实测可用——Openverse（CC BY-SA）、Wikimedia Commons（PD）、The Met Open Access（CC0）、Poly Haven（CC0 纹理）、Iconify（ISC/MIT 图标）；`manifest.json` + `CREDITS.md` 自动生成；许可门槛（NC/ND 拒收、小于最小宽度拒收）生效；SVG→1024² 透明 PNG 成功；字体下载→用户级安装→`font.list` `exact`→中文实排通过（得意黑 / 霞鹜文楷 / Manrope 已装）。端到端成稿见 `designs/free-asset-demo/`。
- **改稿不覆盖**（2026-10-30）：`New-Revision.ps1` 建 `-v2` 副本 → 只改副本 → 导出 `-v2.png`/`-v2.pdf` → `-Seal` 追加封版 sha256。实测：v1 三个文件的 sha256 在整轮改稿后逐字节未变，`REVISIONS.md` 记录 v1/v2 两版及封版核对。
- **AI 生图链路**（2026-10-30 实测）：`generate_image`（智谱 glm-image，1:1/1k）→ 返回 `sha256:` 附件引用 →
  按 `<DSH_HOME>/attachments/v1/objects/<hex前2位>/<hex>` 落盘为 jpg → PhotoCraft 裁掉水印角 + 重采样 1080² + levels/vibrance →
  DesignCraft `file.place` 满版 + 渐变 + 文字 → 交付 `designs/moshan-social/`。**生成图带「AI生成」水印（该渠道关不掉）**。
- **设计系统 + 模板库**（2026-11-06 实测）：3 个模板各跑通一次 —— `poster-a4-photo`（CMYK、PDF/X-4 `valid:true`）、
  `social-1080`（RGB 1080²）、`card-90x54`（90×54mm 印刷）；构建器自动生成 `.dcs` 并调用 `designcraft-cli` 排版导出。
  示例在 `designs/tpl-demo/`。
- **自动 QA**（2026-11-06 实测）：对故意做坏的稿（文字溢出 + 元素越界 + 浅字压浅底）输出 **3 个 error**；
  对模板成品投出 **PASS**；对名片投出 **PASS**。判定用 2× 渲染 + 亮度直方图 p1–p99，避免小字号误报。
- **局部复核**（2026-11-06 实测）：`Inspect-Render.ps1` 对海报输出 full/top/mid/bottom 四张 + 与旧版并排对比图
  （`designs/.inspect/poster-wine/`）。
- **本地生图链路**（2026-11-06 实测）：渠道「本地 Z-Image (sd.cpp)」经 shim `http://127.0.0.1:11436/v1`、模型 `z-image-turbo`。
  `generate_image` 1:1 → 1024×1024；16:9 → 1792×1024；**无水印**；直连 API 单张 37.1s。
  落盘（注意 `name` 是 `.png` 但实际 JPEG，按 `media_type` 落成 `.jpg`）→ PhotoCraft 裁切重采样 2480×1750 + 调色锐化 →
  DesignCraft 排版 → PDF/X-4 `valid: true` + PdfCraft `check {"ok":1}`：成品在 `designs/local-demo/`。
  **2026-11-06 图生图已打通**（用户加了转接层 `F:\AI\sd-cpp\tools\img_shim.py`）：插件 → `:11436`（shim）→ `:11435`（sd-server），
  shim 把 `/v1/images/edits` 翻译成 sd-server 原生 `/sdcpp/v1/img_gen`（`init_image` + `strength=0.6`）。
  实测连续 3 次编辑 + 1 次文生图全部成功、服务未崩：**加元素有效**（右下角加朱红印章成功），**整幅换色调不灵**（只出少量暖斑）。
  想更强改造调 `IMG_SHIM_STRENGTH`（0.75–0.85），调色仍交给 PhotoCraft。回退方案：`sd-cli --init-img`（独立进程，需先停 server）。
- **自写 SVG 链路**（2026-10-30 实测）：手写 `seal-mark.svg`（基本图元 + CJK 文字）→
  DesignCraft `file.place` 400pt 置入，4× 渲染边缘比 2048px PNG 置入更锐（Laplacian 方差 571 vs 329，两者实测均可）；
  PhotoCraft 打开同一 SVG 按内在 900×900 栅格化；`Rasterize-Svg.ps1 -Size 2048` 产出透明 PNG 正常。
- **PdfCraft 交付检查**（2026-10-30 实测）：对 `jingmo-shengzhang.pdf` 跑 `info`（1 页、612.28×858.89pt、PDF 1.6、输出意图 FOGRA39）+
  `check`（`{"ok":1}`）+ `render --dpi 96`（817×1146 PNG）全部成功。
- **9 个设计应用全部安装完成**（2026-10-30，逐台 MSI + SHA-256 与官方 `SHA256SUMS.txt` 逐一比对，全部 MATCH；
  **2026-11-10 全套升级到 0.23/0.19/0.22 一线**）：
  DesignCraft 0.19.0 / PhotoCraft 0.22.0 / VectorCraft 0.23.0 / PdfCraft 0.20.0 / LightCraft 0.20.0 /
  FigCraft 0.17.0 / DeckCraft 0.17.0 / WordCraft 0.17.0 / EffectCraft 0.23.0，每个都带 `<app>-cli.exe`。
  新增 6 个应用的 MCP 也各自握手成功：PdfCraft 200 / LightCraft 406 / FigCraft 19 / DeckCraft 25 /
  WordCraft 18 / EffectCraft 27 个工具（都不强制 roots，除 PhotoCraft 外）。
  **2026-11-10 追加**：EffectCraft 的 MCP（27 工具，`--autosave` + 工作区 roots）已正式挂进 preset，
  与 DesignCraft / PhotoCraft / VectorCraft / reference 一起共 5 条连接、115 个工具。
- **2026-11-10 升级后的复核**：命令目录 542→555（DesignCraft）、945→1000（PhotoCraft）、822→966（VectorCraft）、
  723→761（EffectCraft），**无一条删除**；`Test-Design.ps1` / `Inspect-Render.ps1` 在 0.19.0 上跑通，
  真实稿 `suika-poster-v2.designcraft` 渲染正确。3D 链路（建 comp → 图元/灯光/相机 → 透明出帧）在
  EffectCraft 0.23.0 上端到端跑通（见 `skills/graphic-design/references/effectcraft-3d.md`）。
  **已知误报**：本轮 QA 对该稿报 5 条 `text frame N 对比度 0.0`，但渲染图肉眼可见高对比（旋转/小字号文本帧），
  遇到这种先 `read_image` 看图，别直接改色。

- **风格与参考链路**（v1.3，2026-11-06 实测）：`New-ReferenceBoard.ps1` 改为**专业设计站优先**——
  默认 `Are.na + Design Reviewed`（实测：`soviet constructivist poster` 4 张全对，El Lissitzky「Klinom Krasnim」、
  1920s 构成主义排版、苏联家具海报；`swiss style poster` 8 张里 7 张在瑞士/现代主义语法内；`art deco poster`
  5 张里 4 张对）。新增 `Fonts In Use` / `It's Nice That` 可选项、`-Url`（从 web_search 命中的专业站页面抽 og:image）、
  WebP 自动转 JPEG、下载后质量门槛（宽 ≥ 1200px、≥ 20KB、sha256 去重）与 `designCount` 记账。
  馆藏（AIC/Met/Cleveland/Commons/Openverse）**降级为兜底、默认关闭**：实测 AIC 搜 `constructivist poster` 返回
  1917–18 年一战美国宣传海报，Met 搜 `swiss style poster` 返回瑞士卫队盔甲——已列为「反例」写进 reference-hunting。
  `New-ContactSheet.ps1` 拼版不变。参考板与素材严格分开：`designs/references/<slug>/` 不进成品。

- **参考图联网抓取做成 MCP 一等工具**（v2.1，2026-11-10 实测）：
  `mcp/reference-mcp.mjs` 把「搜图 → 下载 → 质检 → 拼版 → 记账」收成一次工具调用，`design-studio` preset
  直接挂载（`reference-tools`），工具列表里能看到 `mcp__reference__reference_search` 等三个工具。
  - **四条扩展的优势合在一起**：① 一等工具（不再靠模型临时想起调 PowerShell）；② 图片搜索通道
    （Bing Images，自动剔除电商/图库/AI 生图/模板站，设计站与档案加分——实测 `swiss style poster 1960s`
    67 条候选里 52 条被判垃圾，留下的 10 张全是 Behance 真实海报，尺寸 1400–5600px）；③ 共享参考库
    （`designs/references/.reference-index.json` 记签名 + seen 表：同检索词直接命中缓存 0 秒返回，
    跨项目见过的图不再重复下载；`reference_library` 还能把本 MCP 之前抓的老板子一起列出来复用）；
    ④ 形态无关（MCP 自己发 HTTP，web/headless 形态下没有宿主 `web_search` 也能抓）。
  - 脚本侧新增 `-UrlMeta <json>`：搜索引擎拿到的直链没有标题/出处，用它补 `title / pageUrl / source`，
    参考板标签和 `REFS.md` 才有溯源（实测标签从 `ff85f32…` 变成 `50 Swiss Style Posters [Web · behance.net]`）。
  - 实测耗时：冷启动 30–60 秒（含 10 张下载 + 拼版），命中缓存 0 秒；结果含 `timing` 字段。

- **新增铁律 26：不许给画面加「AI 装饰小字」**（2026-11-10，用户要求）：
  用户没要求时，成品**顶部/底部不许自作主张加一行小字英文**——副标题、kicker/eyebrow、版权线、
  `EST. 2024`、`COLLECTION NO.01`、城市名/坐标、假说明文字。这类小字是模型的癖好，不是"细节丰富"：
  不承载信息，还把留白和层级压掉。写进了三处：章程铁律 26、`SKILL.md` 十条翻车点第 10 条、
  `quality-checklist.md` 新增「AI 装饰小字（用户没要求时 = 必须删）」一节、`layout-and-type.md` 翻车清单、
  以及 persona（默认行为）。要加必须真有用户给的信息，或先问用户；用户点名要就按原话做。

- **艺术字体链路**（v1.2，2026-11-06 实测）：VectorCraft 上跑通「逐字错位 → 转曲（`type.createOutlines`）→
  改锚点（`path.moveAnchor`）→ 封套变形（`object.envelope.makeWithWarp`）→ 路径文字（`text.createInPath`）→
  图像填充（`object.clippingMask.make` + 蒙版后描边）」。另实测 5 种路径文字效果（rainbow/skew/3dRibbon/stairStep/gravity，
  `designs/lettering-lab/effects-sheet.png`）、局部钉点变形（`object.puppetWarp`）、字形混合（`object.blend.make`）、
  逐对象随机变换（`object.transformEach`）。示例：`designs/lettering-lab/lettering-lab.png`（五种变形同框的 A3 字形样本）
  与 `designs/lettering-lab/shan-type/shan-type.png`（「山」字内填山景 + 红描边，1080×1350）。

**未验证**
- 「在 GUI 里新建会话并选中该 preset」这一步需要你操作（我无法代替点击）。preset 已激活；挂载异常会在会话里直接报 MCP 连接错误。
- **v2.0 起没有"设计水平自动指标"**：以前用评分表和"平庸信号"衡量，现在这两样已删除。
  想验证改版效果，用同一个 brief（带上完整的风格要求）改版前后各出一稿，**由你自己比对**：
  它是否照你说的做了、有没有偷偷换成它自己的想法。
- `web_search` / `web_fetch` 是否在预设会话里可见，取决于宿主平面（desktop 形态已注入）；若某形态没有，
  agent 会退回 `reference_search`（MCP，自己发 HTTP，不依赖宿主 web 工具）按 `reference-gate.md` 第八节重试，
  并把失败写进过审消息，由用户决定等网络还是降级——不再静默走离线分支。
- 参考板检索质量取决于关键词：馆藏关键词检索偏松，AIC 会把器物/织物一起返回，必须靠 `read_image` 自己筛。
- 字形链路里只剩 `path.setAnchors`（整段换几何）、`object.envelope.makeWithTopObject`（用形状当封套）、
  `object.expand {stroke:true}`（描边转轮廓）没有出图验证；文档里已标「未实测」，正式用之前先拿小稿试。
- `read_image` 视觉复核依赖模型多模态能力；不可用时 agent 按清单做数值化自检并声明。
- 你的具体印厂/打印机的色彩特性（PDF/X-4 通过 ≠ 打样完全一致）。
- PhotoCraft 是早期 alpha：部分 Photoshop 特性（AI 生成、插件）缺失，复杂 PSD 的个别效果可能不还原。

---

## 七、排错

| 现象 | 处理 |
|---|---|
| agent 说某个 MCP 工具不可用 | 分别跑 `designcraft-cli --version` / `photocraft-cli --version`（在 `%LOCALAPPDATA%\Programs\ArtCraft\<App>\`）；不在就重装，或修正 `cordis.patch.yml` 的 `command` |
| `generate_image` 不存在或报「没有可用模型」 | 「设置 → 生图配置」里检查渠道与模型目录；当前默认渠道是本地 Z-Image（`127.0.0.1:11436`，shim） |
| 生图报 502 / `上游不可用` | shim 在但 `:11435` 的 sd-server 没起：让用户跑 `launch.ps1`（或 `start-server.ps1`）；`http://127.0.0.1:11436/healthz` 可看上游状态 |
| 生图连不上（11436 无响应） | shim 没起（`F:\AI\sd-cpp\tools\img_shim.py`）：让用户跑 `launch.ps1`；日志看启动它的终端 |
| `edit_image` 能出图但几乎没变化 | shim 固定 `strength=0.6`，整幅换色调改不动。换更具体的提示词（说明保留什么、改什么）；大改调 `IMG_SHIM_STRENGTH`（0.75–0.85）；换色一律走 PhotoCraft |
| 生成到一半进程消失、事件日志无 assert | 多半是同时跑了 `sd-cli` 和 `sd-server`：两个 6.8GB 模型抢 8GB 显存。**同一时间只允许一个 sd 进程** |
| 刚启动就打请求报 `ECONNRESET` | sd-server 还在加载模型（约 20–30s）；等 `/v1/models` 就绪后再等 5–10s，或先出一张小图预热 |
| 从 DSH 里启动的 sd-server 过一会就没了 | 它被绑在那个 pwsh/job 的进程树上，job 结束即被杀；要脱离会话启动用 WMI `Invoke-CimMethod Win32_Process Create`（命令见技能文档），或你自己在终端跑 `launch.ps1` |
| 落盘后 `read_image` 报「扩展名与实际格式不符」 | 插件的 `name` 是 `.png`，实际是 JPEG；按 `media_type` 存成 `.jpg` |
| AI 图右下角有「AI生成」水印 | 智谱渠道关不掉；换火山方舟 / BytePlus（可在渠道里关 `watermark`），或让 agent 裁切/构图避开，并在交付说明里如实告知 |
| PowerShell 直接把 JSON 传给 CLI 报 `key must be a string` | 引号被 PowerShell 剥掉了；改用 `run --script <json 文件>` / 走 MCP / 把参数写进文件 |
| 小图标置入后特别小 / 模糊 | SVG 没有明确 `width/height`（如 `1em`）；先 `Rasterize-Svg.ps1 -Size 2048` 转 PNG 再置入 |
| 中文变豆腐块 □ | 字体没设中文字体。让 agent「用 font.list 查字体并给所有文字设 Noto Sans SC/Noto Serif SC」 |
| `outside the read root` / `outside the write root`（PhotoCraft） | 图片或输出路径不在工作区内。把文件复制进 `C:\design-workspace`，或改 bundle 的 roots 后重装 |
| PhotoCraft 打开全部失败 | roots 目录不存在（启动即退出）。确认 `--automation-read-root`/`--automation-write-root` 指向已存在的目录 |
| 导出的 PDF 有 RGB 警告 | 印刷稿要用 CMYK 色板（`{"c":..,"m":..,"y":..,"k":..}`）；让 agent 换 CMYK 重出 |
| 照片在版面里糊 | 置入宽度（pt）× 4.1667 > 图片像素宽。让 agent 回 PhotoCraft 重新裁切重采样到 300dpi |
| 印厂说 PDF 有问题 | `pdfcraft-cli check <文件>` 看结构与可打印性，`info` 看尺寸/版本/输出意图；需要时 `pdfcraft-cli edit` 修页序或 `batch` 转 PDF/A |
| preset 列表里没有「平面设计工坊」 | `remove_bundle` 再 `install_bundle`（target 用本目录绝对路径），然后重载 GUI |

---

## 八、许可与致谢

- DesignCraft / PhotoCraft / VectorCraft / PdfCraft / LightCraft / FigCraft / DeckCraft / WordCraft / EffectCraft：
  MIT OR Apache-2.0，© ArtCraft Team（https://getartcraft.com）。
- 本 bundle 的章程、技能文本、图标为本项目原创，随本仓库使用。
- AI 生图由用户配置的渠道与模型提供（当前智谱 `glm-image`）；生成内容的使用受该服务条款约束。
- 引擎文档：`docs/mcp.md`、`docs/agents.md`、`docs/control-protocol.md`（仓库 `storytold/<app>`）。
- 引擎文档：`docs/mcp.md`、`docs/agents.md`、`docs/control-protocol.md`（仓库 `storytold/designcraft`、`storytold/photocraft`）。
- v1.4 随包字体：来自 anthropics/skills 的 `canvas-design/canvas-fonts/`，各自 SIL OFL 1.1（许可文本随包，`assets/fonts/*-OFL.txt`）。
- v1.4 生图提示词模板：来自 ConardLi/garden-skills 的 `gpt-image-2`，MIT（`references/image-prompt-templates/LICENSE-garden-skills.txt`）。
- v1.4 反模板化清单：机制参考 anthropics/skills `frontend-design` 与 pbakaus/impeccable（均 Apache-2.0），本文重写为中文断言式清单。
- v1.4 三方向门与外观账本：机制参考 alchaincyf/huashu-design（MIT），只移植机制与文案，未随包装其 226MB 资产。

---

## 九、v1.4 市场调研与能力整合（2026-11-06）

这一版做了一件事：**先调研市面上最好的平面设计 / 作图 skill 与 MCP 插件，再把真正有增量的那几样装进这个 agent。**
完整调研见工作区 `research/skills-market.md`（skills / prompt 包）与 `research/mcp-market.md`（MCP 服务器）。

### 9.1 新增的第四条产线：HTML 画布（`html-graphics` 技能）

Chromium 当绘图引擎：写 HTML/CSS/SVG → 无头渲染 PNG/PDF。**零 npm 依赖**——`scripts/render.mjs` 直接用 Node 24
的 `fetch` + 内置 `WebSocket` 通过 CDP 驱动本机 Edge/Chrome（也兼容 Playwright 缓存里的 Chromium）。

| 能力 | 命令 |
|---|---|
| 渲染 PNG | `Render-Html.ps1 -In x.html -Out x.png -Width 1080 -Height 1350 -Scale 2` |
| 印刷尺寸 | `-Width 210 -Height 297 -Unit mm -Dpi 300`（A4@300dpi ≈ 2481×3509） |
| 长图 | `-Width 1080 -FullPage` |
| 单元素/矢量 | `-Selector svg` / `-Selector "#cover"` + `-Transparent` |
| PDF（仅屏幕） | `-Pdf` |
| **自动审计** | `-Audit`：越界 / 文本裁切 / 坏图 / 横向滚动 / 小字 / 色数，**退出码 5 = 有阻塞问题** |
| 数据图 | `scripts/chart.py --kind bar\|line\|donut --data data.json --out chart.svg`（matplotlib，中文已配） |

配套：`templates/` 4 份起手稿（A4 海报 / 社媒 1080 / 长图 / 界面稿），`references/css-recipes.md`
（尺寸表、渐变/颗粒/duotone/遮罩、文字效果、图表、静默失败点）。
端到端示例见设计工作区 `designs/html-demo/`（AI 山景照片 + 渐变压暗 + 噪点 + Gloock 标题 → A4@300dpi，audit 0 error）。

**边界（写进章程铁律 20）**：Chromium 只出 RGB、PDF 中文复制乱码 → 印刷交付必须回 DesignCraft/VectorCraft
用 CMYK 重排文字；HTML 只负责屏幕稿，或作为印品的照片/底纹层。**文字不做位图。**

### 9.2 从市场吸收的四样东西

| 来源（许可） | 吸收方式 | 文件 |
|---|---|---|
| **anthropics/skills · canvas-design**（Apache-2.0） | 随包 **54 个 OFL 字体文件 / 29 个家族**，含许可文本；HTML 可 `@font-face` 直引，ArtCraft 里装用户级 | `skills/graphic-design/assets/fonts/`（`FONTS.md` 对照表） |
| **ConardLi/garden-skills · gpt-image-2**（MIT） | **17 类 / 93 个结构化生图提示词模板** + 压缩配方（gpt-image-2 → z-image-turbo 20–60 词） | `references/image-prompt-templates/` + `references/image-prompt-recipes.md` |
| **anthropics/skills · frontend-design** + **pbakaus/impeccable**（Apache-2.0） | 反模板化清单：五类 2026 AI 视觉签名 + 确定性排印规则，红灯/黄灯分级 | 曾是 `references/anti-slop.md`；**v2.0 已删除**（它把用户的选择当成错误）。来源仍列此致谢 |
| **alchaincyf/huashu-design**（MIT，只抄机制） | **三方向门**（六候选 → 三版真初稿 → 摆出来等选 → `direction-approved.md`）+ **外观账本**（跨项目防同质化） | `references/directions-gate.md`、`scripts/Get-DesignLedger.ps1`、`scripts/Add-DesignLedger.ps1` |

**没有装的（附理由）**：OpenAI 的 skills 仓库无 LICENSE（不可 vendor）且 7 个 `figma-*` 全依赖 Figma MCP；
Canva 官方 skill 全部要 `mcp.canva.com` + 账号（`bulk-create` 还要 Enterprise）；Stitch skills 依赖 Stitch MCP；
vercel 的 `web-design-guidelines` 运行时还要联网拉正文；`impeccable` 本体是自包含二进制 + 默认联网拉方向目录，
只取它的规则文本；`huashu-design` 整包 226MB 且重心是 HTML 原型/动画/PPT，只抄机制。

### 9.3 MCP 插件：只留最划算的一个口子

调研结论：`@deepseek-ai/dsh-mcp-client` **只支持 `stdio` / `streamable-http`，没有 OAuth，也不自动重连**
（现有 `reconnect:` 字段可能被忽略）。所以 Figma 远程 MCP、Canva 都挂不上；Playwright MCP / 图表 MCP
的工具 schema 每轮都要重发，性价比低于我们自己的脚本（`Render-Html.ps1`、`chart.py`）。

因此 `cordis.patch.yml` 末尾留了一段**注释掉的 Figma 只读导入**（`figma-developer-mcp`，2 个工具，只要 PAT，
不需要 Figma 桌面端）：客户给 Figma 链接时按注释启用即可。素材类 MCP（Iconify/Unsplash/Openverse）一律不挂——
`Fetch-FreeAsset.ps1` 已经覆盖且带许可证白名单 + manifest + CREDITS，MCP 只返回 JSON、不落盘不记账。

### 9.4 生效方式与验证

- **技能文件**（`skills/`）在新会话里即生效；**preset 定义 / persona / MCP 列表**在 bundle patch 里，
  需要**重启 DSH**（或 remove_bundle → install_bundle）后新建会话才吃新配置。
- 本版已验证：
  - 用 `dsh --profile headless --patch <bundle>\cordis.patch.yml --dump-config` 组合成功，`preset-design-studio` 正常展开、
    `!!js` 路径表达式解析到 bundle 目录、persona 新段落已生效；
  - `Render-Html.ps1` 四个模板全部出图（PNG/PDF），audit 在正常稿上 `errors: 0`，在故意做坏的稿上报
    4 个 error（越界 / 裁切 / 坏图 / 横向滚动）并退出码 5；
  - 300dpi A4、2× 社媒、长图 `--full-page`、SVG `--selector --transparent`、本地 `@font-face` 字体全部通过；
  - `chart.py` bar/line 出图（SVG + 透明 PNG），中文字体解析到 Microsoft YaHei；
  - 账本脚本 `Add-DesignLedger.ps1` / `Get-DesignLedger.ps1` 实跑通过（写入、回读、avoid 摘要）；
  - 字体 54 个文件头校验通过；提示词模板 93 个 + MANIFEST + MIT 许可文件到位；
  - **真实合成稿**：AI 山景照片满版 + 渐变压暗 + 噪点 + 随包 Gloock 字体 → A4@300dpi 2481×3509，audit `errors: 0`；
  - `Test-Design.ps1` 新增的 3 类排印检查用合成文本验证：全大写眉标 3 条、`A · B · C` 1 条、连续编号 `01–03` 1 条，全部命中；
    对真实稿 `jingmo-shengzhang.designcraft` 仍是 `0 errors, 0 warnings`（未误报）。
- **未验证**：在 GUI 里新建会话并选中「平面设计工坊」这一步需要用户点击；`read_image` 视觉判断仍依赖模型多模态能力；
  Figma 挂载未实测（没有 PAT）；headless 侧无法直接选中该 preset（headless 没有 preset registry），
  所以「会话里 agent 真的自己调用这些技能」没有自动化跑通，逻辑与脚本是独立实测的。

---

## 十、v1.5 参考关（2026-11-06）

这一版只解决一个流程问题：**参考不能是「agent 自己看过就算」，必须联网找够、读透、并且交付给你过审。**

### 10.1 三条新规则（写进章程、技能与 persona）

| 规则 | 落点 | 效果 |
|---|---|---|
| **必须联网搜集参考图** | 章程 §1.5 / 铁律 23；`reference-gate.md` §二；persona | 硬下限 ≥ 4 张、≥ 3 张专业设计源、≥ 2 来源/检索词；联网失败要重试并如实上报，**不许静默降级**；全板馆藏不许过审 |
| **参考图交付用户过审才能继续** | 章程 §1.5 / 铁律 23·25；`reference-gate.md` §五；persona | 交付四件套（编号整板图 + 逐张清单 + 精读结论 + 三问；**v1.6 起为五件套，加素材板**），用户原话逐字写进 `designs/<slug>/refs-approved.md`；**该文件不在：不许写设计决策单、不许开三方向门、不许建画布** |
| **设计要全面学习参考图** | 章程 §1.5 / 铁律 24；`reference-hunting.md` 第 3.5 步；`reference-gate.md` §三 | 每张参考一张 11 字段精读卡（网格/层级/色彩/字体/图文/母题/节奏/3 条可迁移规则/3 件不抄/被哪条 DNA 采用）+ 交叉分析（3 共性/3 差异/1 打架取舍）；DNA 卡每个字段带 `#NN` 溯源；只看缩略图就写 DNA = 没做 |

### 10.2 静默时钟（你太久不回，它自动继续）

摆出参考过审或三方向后，agent **结束这一回合**，并用 `schedule_create` 给本会话设一个一次性唤醒
（默认 **10 分钟**，可 5–15）。到点没回复：写 `silent-approve`（按它点名的默认范围），回一句
「到点没回，我先按默认继续，随时可推翻」，然后继续下一步；你一旦回复，它先删掉定时任务再按你说的做。
**不许把 `silent-approve` 写成用户认可**；没有 `schedule_create` 时退回普通提问并明确告知「无法自动继续」。

状态文件：`designs/<slug>/refs-gate.json`（deadline / mode / taskId / state）。

### 10.3 新增/改动的文件

- 新增 `skills/graphic-design/references/reference-gate.md`（参考关总纲：门槛 / 精读 / 过审 / 静默时钟 / 门禁）；
- 改 `reference-hunting.md`（全面精读 11 字段、DNA 溯源、联网失败不许静默降级、版权条更新）；
- 改 `directions-gate.md`（参考关前置、Phase 1/6/7 接静默时钟）；
- 改章程 `design-studio.md`（§0 环境自检、§1.5 重写、§2 决策单加参考行、铁律 18 更新 + 新增 23–26、§五 升级、§六 工具图）；
- 改 `SKILL.md`（description、五分钟上手第 2 步、翻车点、脚本/参考文件表、交付哲学）；
- 改 `cordis.patch.yml` persona（三条新规则 + 静默时钟，`--dump-config` 已解析通过）；
- 改 `locale/*.json`、`package.json` 版本号。

### 10.4 生效方式

- 技能与章程是文件读取，**新会话即生效**；persona / preset 定义在 bundle patch 里，
  需要 `remove_bundle` → `install_bundle`（或重启 DSH）后新建会话才吃新配置；
- `dsh --profile headless --patch <bundle>\cordis.patch.yml --dump-config` 已验证 YAML 与 `!!js`
  路径表达式解析正常（2026-11-06）；
- **未验证**：真实会话里「摆参考 → 设时钟 → 到点自动继续」这一整条链路没有端到端跑过（需要用户配合或等 10 分钟）；
  静默时钟依赖宿主挂载 `schedule_*` 工具，桌面形态已挂，其它形态若没有会走阻塞等待并说明。

## 十一、v1.6 素材关（2026-11-06）—— 已由 v2.0 取代

> **这一节是历史记录。** 其中的"配额、≥2 张、≥30% 面积、每单 ≥2 次交接、素材关必做"等硬规则
> **已在 v2.0 删除**：画面构成现在由用户要求和 `style-dna.md` 决定，不含任何张数或面积下限。
> 现行规则见章程 §1.8 与 `material-pass.md`。

这一版解决的是**「什么都能用矢量画」的默认习惯**：以前素材只是「缺了才去取」，现在**素材是第二件必做的事**，
而且必须和位图软件来回联动，不许把整张海报画成矢量。

### 11.1 流程变了

```
改前：需求 → 参考关（搜图/精读/过审）→ 设计决策单 → 三方向门 → 素材（缺了才找）→ 排版
改后：需求 → 参考关（搜图/精读）→ 素材关（与过审并行：取素材 + 生图 + PhotoCraft + 素材板）
      → 参考板 + 素材板同一条消息过审 → 设计决策单 → 三方向门 → 置入素材 → 排版 → 看稿 → 交付
```

### 11.2 四条硬规则（写进章程、技能与 persona）

| 规则 | 落点 | 效果 |
|---|---|---|
| **素材关每单必做，不是缺素材才做** | 章程 §1.8 / 铁律 29；`material-pass.md` §一；SKILL 第 2a 步；persona | 参考板一成型就开素材关，与等过审并行；素材板 `materials-board.png` 随参考板一起交付；建画布前 `material-plan.md` 与对应档位张数（海报类 ≥2）处理完的位图必须已在盘上 |
| **成品里必须真有位图** | 章程 §1.8 / 铁律 27；`material-pass.md` §三 | 海报/封面/社媒/Banner/传单/菜单/邀请函 ≥2 张位图（1 主视觉 + 1 底纹/背景）且位图面积 ≥30%；画册每页 ≥1；信息图/长图/数据图 ≥1；纯矢量例外（logo/图标组、用户明确要的纯文字海报、纯图表）要写进决策单与交付说明 |
| **背景要专门做** | 章程 §1.8；`material-pass.md` §3；`assets-generation.md` | 背景单独出图（留空位、`no text`、2–4 变体、按成品比例），底纹优先 CC0 纹理；选定前把标题色压上去做对比测试 |
| **位图 ⇄ 矢量来回走** | 章程 §1.8 / §2.6 / 铁律 28；`material-pass.md` §6；两条 pipeline | 每单 ≥2 次跨引擎交接（≥1 位图→矢量、≥1 矢量→位图），6 条配方 R1–R6；交付说明里写「素材链」 |

### 11.3 新增/改动的文件

- 新增 `skills/graphic-design/references/material-pass.md`（素材关总纲：时机 / 配额 / 素材板 / 背景 / 生图 / 联动 R1–R6 / 反模式 / 闸门）；
- 改 `agents/design-studio/design-studio.md`（§一 素材优先身份、§1.5 顺序与过审五件套、新增 §1.8 素材关、§2 决策单加素材行、
  §2.5 更名与定位、§2.6 加联动规则、§3.5 位图全检、§4A 置入层级、铁律 27–29、§六 工具图与缺口）；
- 改 `skills/graphic-design/SKILL.md`（description、五分钟上手第 0/2a/4 步、翻车点第 9 条、参考文件表、交付哲学）；
- 改 `cordis.patch.yml` persona（素材关 + 位图/矢量交接）；
- 改 `locale/*.json`、`package.json`、本 README。

### 11.4 生效方式

- 技能与章程是文件读取，**新会话即生效**；
- persona / preset 在 bundle patch 里，改动要 `remove_bundle` → `install_bundle`（或重启 DSH）后新建会话才吃新配置；
- **未验证**：素材关的配额（按档位张数、海报类 ≥30% 面积、≥2 次交接）没有脚本能自动量，靠 `material-plan.md`、
  素材板与交付说明留痕；生图质量（假字/跑题）仍要逐张 `read_image` 人工判断。
