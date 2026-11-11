---
name: graphic-design
description: 平面设计的完整打法（ArtCraft 四引擎 + HTML 画布 + EffectCraft 3D 静帧）：海报/封面/社媒图/logo/图标/信息图/长图/名片/菜单/邀请函/画册/产品包装 mockup。用户要求逐条锁定（brief-lock），风格按用户原话当场联网爬设计数据库得出（style-research，无内置风格目录），参考过审后才动手；含素材取材与许可、矢量/位图/3D 交接、DesignCraft/VectorCraft/PhotoCraft/EffectCraft 命令配方、自动 QA 与改稿留版本。做任何平面设计稿、定风格、找参考、改稿时使用。
---
# 平面设计技能（graphic-design）

把自然语言需求做成**真正符合用户要求**的可交付平面设计。配合章程（`agents/design-studio/design-studio.md`）使用：
章程管「流程与权威关系」，本技能管「设计与命令的具体做法」。

## 什么时候加载本技能

- 用户让你做海报、封面、社媒图、传单、名片、菜单、邀请函、信息图、长图、Banner、包装。
- 用户说「帮我设计一个…」「做张图」「出个海报」但没有给规范。
- 你需要具体的版式参数、字号阶梯、配色做法或 DesignCraft / VectorCraft 命令配方。
- 你需要**按用户描述去查风格**（见 `references/style-research.md`），或找参考（`references/reference-hunting.md`）。
- 主标题要做**艺术字体 / 字形改造 / 变形字 / 图像填充字 / 路径文字**（见 `references/lettering-and-display-type.md`）。
- 缺照片/底纹/图标/字体，要自己去互联网取可商用的免费素材（见 `references/free-assets.md`）。

> **本技能不提供风格标准。** 没有风格图鉴、没有色数上限、没有留白配额、没有"平庸信号"、没有风格评分。
> 用户要什么就做什么；用户没说的才由你按内容判断，并写进决策单供他推翻。

## 五分钟上手（命令级流程）

0. **先锁需求，再选画面来源**：把用户的每一条明确要求逐字写进 `designs/<slug>/brief-lock.md`（R01…）。
   画面来源顺序只是效率参考：用户给的 → `designs/assets/` → 免费素材站 → AI 生图 → 自绘矢量 → 占位。
   **用户指定了画面类型（要照片/不要照片/纯字/纯矢量/线稿）就按他说的做。**
   引擎：单件成品（海报/封面/社媒图/logo/图标/信息图）→ **VectorCraft**；多页 → **DesignCraft**；
   照片处理 → **PhotoCraft**；长图/信息图/套图/数据图/界面稿 → **html-graphics（产线 D）**；
   产品/包装 mockup、等距结构、立体字 → **EffectCraft 3D 静帧（产线 E）**。
1. **定尺寸** → `references/format-presets.md` 查 pt 值；产线 D 用 `../html-graphics/references/css-recipes.md` 的 px 尺寸表。
2. **风格研究关（硬门槛，不可跳过）** → `references/style-research.md` + `references/reference-gate.md`：
   ① 用用户原话造检索式（中英各一组），**不许**从任何内置目录挑风格；
   ② 当场联网抓真实设计，**范围是全球互联网**：首选 `reference_search`（本 bundle 的 MCP 一等工具：
      Bing 图搜 + 内置四站 + 任意 `url` 直链 → 下载/质检/去重/拼版/记账一次完成；同检索词命中共享库缓存，
      `refresh:true` 才重抓，旧板子用 `reference_library` 复用）；没有这个工具时退回
      `web_search` + `New-ReferenceBoard.ps1 -Url/-Query`；来源不限（设计站、社交平台、品牌站、档案馆、旧物照片、影视截图都行）；
      **参考不需要版权**（它不进成品）；
      硬下限 ≥4 张、≥2 来源/检索词、宽≥1200px；不够就换词换平台，不许凭记忆画；
   ③ 逐张 `read_image` 精读，写 `reference-study.md`（**7 条** + 交叉分析 + 每条对应哪条需求）；
   ④ 合成 `style-dna.md`：每个参数标出处（`R0N` 用户原话 / `#NN` 参考）；
      **参考与用户原话冲突时删参考，不删用户**；
   ⑤ 交付过审：整板图 + 清单 + 精读结论 + DNA 摘要 + 三问；用户原话逐字进 `refs-approved.md`；
      **没有它不许写决策单、不许建画布**；
   ⑥ 静默时钟：摆出后结束回合并设一次性唤醒（`schedule_create` → `this_session`，默认 10 分钟）；
      到点无回复按用户已给要求继续并记 `silent-approve`；用户回复先删定时任务。
3. **画面来源（素材关）** → `references/material-pass.md`：
   取材顺序 用户素材 → `designs/assets/` 已有 → 免费素材站 → AI 生图 → **程序化网格（3D）** → 自绘矢量 → 占位。
   **张数、面积、要不要位图，由用户要求和内容决定，没有配额。**
   背景需要时单独出（prompt 留空位、`no text`、一次 2–4 变体、按成品比例）。
   产出 `material-plan.md`（M01… 用途/文件/来源/许可/尺寸/处理/是否入选）、manifest/CREDITS（+ AI 的 `sources.md`）。
   跨引擎交接按画面需要来，没有"每单必须 2 次"的硬要求。
4. **定结构** → `references/layout-and-type.md` 里有网格、字号阶梯、版式配方（**工具书，不是标准**；
   用户给了自己的做法就以用户为准）。
5. **要立体件？先分清是"形"还是"光"。** EffectCraft 是**虚拟摄影棚，不是建模器**：
   图元只有六个、材质只有标量、**没有任何贴图/凹凸通道** —— 所以球永远只能是球。
   几何按这个优先级来：**客户模型 → 程序化网格（`scripts/proc-mesh.py` → `.glb`）→ AI 生图 → 图元（仅规则几何体）**。
   有机物/写实主体**禁止用图元顶替**，生图不可用时要**升级**、不是换方案。详见 `references/effectcraft-3d.md`
   与 `references/procedural-mesh.md`。
6. **要图案 / 插画 / 图形母题？默认走 3D：先建模，再平面化。**
   建几何（`scripts/proc-mesh.py` / 图元拼装 / 客户模型）→ **压平光**（要高 Ambient、去高光，否则出渲染味）
   → `render-frame --transparent` → 位图直接用，或 `imageTrace.makeAndExpand` 转成可编辑路径。
   完整配方（四种灯光、trace 参数、图案化、验收）见 `references/3d-to-graphic.md`。
   **不要**用 `draw_shape`/`path.create` 凭描述手绘复杂插画或图标——模型的空间与曲线控制很弱；
   手写矢量只留给简单几何（矩形/圆/线/箭头）与文字。艺术字见 `references/lettering-and-display-type.md`。
   **素材站下的图如果画质差、风格不对、构图不可控 → 回 3D 自己搭，不要凑合。**
7. **取素材**（`references/free-assets.md`）：
   `Fetch-FreeAsset.ps1`（Cleveland/Met/Wikimedia/Openverse/Poly Haven/Iconify/直链，自动写 `manifest.json` + `CREDITS.md`）
   → 小图标/`1em` 尺寸的 SVG 用 `Rasterize-Svg.ps1` 转到目标像素 → 字体用 `Install-UserFont.ps1` 装用户级。
   **只看 CC0 / 公有领域 / CC BY / CC BY-SA / OFL 等素材。**
   AI 生图：先查 `references/image-prompt-recipes.md`（只打开命中的那一个），压成 20–60 词 →
   `generate_image` → 按 `media_type` 落盘 → PhotoCraft → 进版面；**画面里不写文字**。
8. **每一张进版面的位图做预处理**（`references/photocraft-pipeline.md`）：
   `doc_open → image.crop（裁切+重采样）→ levels/vibrance → smartSharpen → doc_export`。
   用户要原片直出、要低清复古、要不调色，就照他说的跳过对应步骤。
9. **排版 = 写 `design.json` 交给编译器**（`layout/DESIGN-SPEC.md` 是语法唯一事实源）：
   ```bash
   LAYOUT="C:/Users/<you>/.dsh/bundles/design-studio/skills/graphic-design/layout/layout.mjs"
   node "$LAYOUT" lint designs/<slug>/design.json           # 秒级，0 引擎
   node "$LAYOUT" run  designs/<slug>/design.json --out designs/<slug> --slug <slug> --scale 2
   ```
   **有 error 不会出片**（`skippedExport: true`）；`--force` 只用于带错排查。
   页面 → 栅格（`columns`/`gutter`/`margins`）→ 字号阶梯 → 色板 → 块（顺序即叠放）。
   文字块不写 `h` = 自动高度（引擎实测）；`stack` 做纵向流，`row` 做分栏。
   报告里 `text.overflow` 的 `fix` 直接照做（加高到 Npt / 字号 ×0.93）。**不要再手写几十条命令摆坐标。**
   `templates/build.mjs` 只作为旧版槽位模板保留；有 `layout.mjs` 后不再需要它来出新版式。
10. **看稿（缺一不可）**：
   ① **自动 QA**：先看 `layout.mjs run` 的报告——`ok:true` 且 `issues` 无 error 才算过；
      `text.overflow` / `box.outOfPage` 是硬错，`box.overlap` / `text.contrast` 要人工判断。
      补充关：`Test-Design.ps1 -Design <file>`（只认 `.designcraft`）查 overset / 越界 / 空帧 / 文字不可见，**必须 0 error**；
      它**不判断风格**（色板数、元素数、版式手法都不是错误）。
   ② **局部复核**：`Inspect-Render.ps1 -Design <file>` 出 `-full/-top/-mid/-bottom` 四张，逐张 `read_image` 看；
      改稿前后用 `-Compare` 出并排图。这两支脚本只认 `.designcraft`；
      产线 A 改走 `render_preview` → `read_image` → `doc_inspect` 对数字 → `export {rect, scale:3}` 看局部。
   ③ **需求核对**：逐条对 `brief-lock.md`，每条给出落实证据；偏离必须先问用户。
   **用户要改的稿 = 新版本**：`New-Revision.ps1 -Project designs\<slug> -Note "<用户原话 + 实际改动>"` 建副本，
   只改副本、只导出到 `-vN`，原稿不动；改完 `-Seal` 核对 sha256。
11. **交付** → 产线 C：`export_png` / `file.exportPdf` / `save_document`；
    产线 A：`export {format:"png", path, scale:2}` + `document.exportPdf {standard:"pdfX4"}` + `save_file`。
    印刷稿再用 PdfCraft 复核（`pdfcraft-cli check`）；有扒来的素材附 `CREDITS.md` 与许可证；
    改过稿附 `REVISIONS.md`。**QA 没过、需求没逐条核对过的稿不许说「完成」。**

## 十条最容易翻车的点

1. **单位**：DesignCraft 内部是 pt（1mm = 2.8346pt）。A4 = 595.28 × 841.89pt。别把 mm 当 pt 填。
2. **坐标系**：原点在 spread 左上角，y 向下；对页（facing）右页 x 从页宽开始。
3. **参数靠查不靠背**：DesignCraft 用 `list_commands`、PhotoCraft 用 `command_list`、
   VectorCraft 用 `command_list`（MCP）或 `vectorcraft-cli commands`（CLI，**没有 `describe`**，966 条每条带 `params`；
   **0.23 起多传未声明的键会硬报错**）；DesignCraft CLI 有 `describe <id>`。
4. **每件物体自己带颜色。** VectorCraft 的 `set_paint` 是「改当前选中 + 改新画默认值」双作用，
   刚画完的对象仍选中——再调一次就把它改色。用 `draw_shape {…, fill}` / `add_text {…, color}` 一物一色，或显式传 `ids`。
5. **CLI 路径的 JSON 只走 `--commands` 文件。** 从 PowerShell 传 `--params '{"…"}'` 会被吃掉双引号。
6. **先锁需求，再谈画面。** 顺序是：需求锁 → 风格研究（联网）→ 过审 → 画面来源 → 决策单 → 建画布。
   `refs-approved.md` 不在就动手 = 返工；`brief-lock.md` 里的要求没落实 = 交付不合格。
7. **待用户拍板的停顿必须挂静默时钟。** 摆完参考就结束回合，设 10 分钟一次性唤醒；
   到点按用户已给要求继续并记 `silent-approve`，用户回复先删定时任务。**不许把 silent-approve 写成用户认可。**
8. **字形叠加要能解释。** 每一层都得回答「它在帮什么」，叠完焦点和层级不能塌；说不清的那层删掉
   （详见 `lettering-and-display-type.md`）。
9. **用户的要求不会被"素材不够"或"生图挂了"抵消。** 工具不可用就换一条能达到同一效果的路，
   或者告诉用户、给替代方案；不许擅自把用户要的画面换成你觉得方便的那种。
10. **不要加"AI 装饰小字"。** 用户没要求时，画面顶部/底部不许自作主张加小字英文（副标题、kicker、
    版权线、`EST. 20XX`、`COLLECTION NO.01`、城市名/坐标、假说明）。它不是丰富，是噪音：
    不承载信息，还把留白和层级压掉。要加先问用户；用户点名要就按原话做。

## 工具与脚本（`scripts/`，全部实测过）

| 工具 | 干什么 | 关键坑 |
|---|---|---|
| MCP `reference_search` / `reference_library` / `reference_status` | **风格研究第一步 · 参考板（首选）**：`mcp/reference-mcp.mjs` 自建 MCP。Bing 图片搜索（自动剔除电商/图库/AI 生图/模板站）+ 内置四站 + 任意页面/图片直链 → 下载 → 质量门槛 → 去重 → `refs.json` + `REFS.md` + `board.png`，并记入共享参考库（`designs/references/.reference-index.json`），同检索词命中缓存、跨项目去重 | 传 `workspace`（会话工作目录绝对路径）；首次 30–60 秒；`refresh:true` 才重抓同一块板；参考图不入成品 |
| `New-ReferenceBoard.ps1` | 参考板脚本（MCP 的底层实现，也可单独用）：`-Url` 喂任意页面或图片直链，或 `-Query` 用内置四站（Are.na / Design Reviewed / Fonts In Use / It's Nice That）→ 质量门槛（宽≥1200px）→ `refs.json` + `REFS.md` + `board.png` | 只做研究、不入成品；关键词来自用户原话；来源不限；至少 4 张、2 个来源/检索词；`-UrlMeta <json>` 可给直链补标题与出处 |
| `New-ContactSheet.ps1` | 多图拼成带编号的拼版图 | `-Images` 可传 `;`/`\|` 分隔或一个目录；GDI+ 不支持 WebP |
| `Fetch-FreeAsset.ps1` | 从开放素材源检索并下载可商用图片/纹理/图标/字体，写 `manifest.json` + `CREDITS.md` | 微信式 UA 会被 Wikimedia 429；Met v1/search 已退役（脚本用 v1.1） |
| `Rasterize-Svg.ps1` | SVG → 指定像素的透明 PNG（Edge 无头） | `width="1em"` 的 SVG 必须先光栅化 |
| `Install-UserFont.ps1` | 字体装进当前用户字体目录 + HKCU 登记 / 卸载 | 只装 OFL 等可商用字体；不写 `C:\Windows\Fonts` |
| `New-Revision.ps1` | 改稿前复制成 `-v2`、`-v3`…，维护 `REVISIONS.md`；`-Seal` 追加 sha256 | 不复制渲染件（会拿上一版画面冒充新稿） |
| `Test-Design.ps1` | 自动 QA：overset / 越界 / 空帧 / 重叠 / 文字几乎不可见；`-Json`、`-Strict` | 判对比用 2× 渲染 + 亮度直方图；**不判断风格** |
| `Inspect-Render.ps1` | 2–3× 渲染并切 `top/mid/bottom` 局部图；`-Compare` 并排 | 局部图才是细节真相 |
| `Get-DesignLedger.ps1` / `Add-DesignLedger.ps1` | 外观记录：读写 `designs/_ledger.json`（配色/字体/骨架/主色相） | **只是记录，不是限制**；可以用来自查"我最近是不是老用同一招"，但不能据此改掉用户的要求 |
| `mcp-client.mjs` | 上面的脚本用的通用 MCP 客户端 | `--cli <exe> --cli-args '["mcp"]'` 可换引擎 |
| `proc-mesh.py` | **程序化有机网格**：球面 + 多倍频位移 + 凹点 → 自包含 `.glb`（几何 + albedo + normal + MR 全嵌入）→ `layer.newModel` | 用法与调参见 `references/procedural-mesh.md`；先 `--dry-run` 看 `silhouette_is_perfect_circle` |

产线 D 的脚本见 `../html-graphics/scripts/`：`Render-Html.ps1`（渲染 + 审计）、`render.mjs`、`chart.py`。

本机 PowerShell 执行策略禁止直接跑 `.ps1`，一律用
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<脚本绝对路径>" <参数>`；脚本文件必须 **UTF-8 with BOM**。

## 参考文件路由（按"你正在做什么"查，**不要**按目录通读）

> 读太多的根因不是文件多，而是**每个文件看起来都同样该读**。下表是唯一入口；
> **"读多少"是硬约束**：‡ = 只查表，不许通读；† = 命中时才读；其余 = 该场景一次读完。
> 一次任务通常只命中 **2–3 行**；如果你打开了 5 个以上文件，说明你在闲逛。

| 你正在做什么 | 读哪个 | 读多少 |
|---|---|---|
| 任何新稿开工 | 本文件 §五分钟上手 0–2 | 已在上下文 |
| 定尺寸/出血/安全区 | `references/format-presets.md` | ‡ 只查表 |
| 造检索式 / 抓参考板 | `references/style-research.md` §二–三 | 两节 |
| 参考数量与来源门槛 / 过审 / 静默时钟 | `references/reference-gate.md` §二–六 | 该关一次读完（**唯一事实源**） |
| 写 `reference-study.md` | `references/reference-gate.md` §四 的模板 | 只抄骨架（7 条） |
| 动笔前门禁检查 | `references/reference-gate.md` §七 | 一段 |
| 不知道去哪找 / 感觉找错了 | `references/reference-hunting.md` §一–三 | 三节，别读流程段 |
| **用户没给方向，要摆 2–3 个候选** | `references/directions-gate.md` | 全读（5 KB，一次） |
| 画面从哪来 / 素材板 | `references/material-pass.md` §一–四 | 四节 |
| 背景 / 底纹专项 | `references/material-pass.md` §五 | 一节 |
| 素材⇄版面联动 | `references/material-pass.md` §七 | 一节 |
| 找免费照片 / 纹理 / 图标 | `references/free-assets.md` §1–2 | ‡ 许可表 + 源表 |
| 跑 `Fetch-FreeAsset` / 光栅化 SVG / 装字体 | `references/free-assets.md` §3–5 | 命令段 |
| 自己画矢量（SVG / 描摹 / 程序化） | `references/assets-generation.md` §〇–一 | 两节 |
| 出 AI 底图 / 背景 | `references/assets-generation.md` §二 | 一节 |
| 选生图模板 | `references/image-prompt-recipes.md` §三 | ‡ 只查表，选一类 |
| 写生图提示词 | `references/image-prompt-recipes.md` §四 + **命中那 1 个**模板文件 | 1 模板 |
| 改已有图（去物 / 换背景 / 局部） | `references/image-prompt-recipes.md` §五 + `editing-workflows/` 1 个 | 1 模板 |
| 要自造提示词模板（罕见） | `references/image-prompt-templates/prompt-writing.md` | 仅此场景 |
| 位图进版面前处理 | `references/photocraft-pipeline.md` §1–4 | 四节 |
| 多页 / 模板 → 产线 C | `references/designcraft-commands.md` | 全读（9 KB） |
| **写 design.json / 排版出稿（产线 C 主路径）** | **`layout/DESIGN-SPEC.md` + `layout/examples/`** | **一次读完（8 KB，动手前必读）** |
| **报告里出现 overflow / 越界 / 重叠** | `layout/DESIGN-SPEC.md` §四 校验与报告 | 一节 |
| 单件成品 → 产线 A | `references/vectorcraft-pipeline.md` §〇–五 | 五节 |
| **图案 / 插画 / 图标型母题 / 装饰元素（首选画法）** | `references/3d-to-graphic.md` | 全读（6 KB，一次） |
| **产品 / 包装 / 立体字 / 有机物立体件 → 产线 E** | `references/effectcraft-3d.md` §一–四 | 四节 |
| **要给有机物做真几何（程序化网格）** | `references/procedural-mesh.md` | 全读（5 KB，一次） |
| 印前 / PDF 复核 | `references/craft-cli-recipes.md` §1 | 一节 |
| 版式 / 字号 / 配色 / 中文排版 | `references/layout-and-type.md` | 工具书，按需取配方 |
| 主标题艺术字 | `references/lettering-and-display-type.md` §一–二 | 两节 |
| 交付前自检 | `references/quality-checklist.md` | 全读（4.8 KB，每稿一次） |
| 长图 / 信息图 / CSS 稿 | `../html-graphics/references/css-recipes.md` | 一节 |

**另外**：`assets/fonts/` 是随包 OFL 字体（54 文件 / 29 家族，清单见 `FONTS.md`）；`layout/` 是版式编译器
（`layout.mjs` + `DESIGN-SPEC.md` + `examples/`，**产线 C 的主路径**）；`templates/` 是旧版槽位模板
（`build.mjs --list`、`design-tokens.json`——token 仍被 `layout.mjs` 复用）。
`references/image-prompt-templates/` 整棵子树（93 个模板 / 约 78 万字节）**只允许经上面第 16–18 行单条进入**，禁止 `ls` 式探索；
`MANIFEST.json` 只作索引查询，`LICENSE-garden-skills.txt` 只在交付署名时读。

## 交付哲学

- **用户是唯一标准。** 他说要什么就做什么；他说的每一条都要有落地证据。
- **风格是查出来的。** 从他的话出发，当场联网找真实设计，读成参数，交他确认。
- **画面来源听用户的。** 要照片、要插画、要纯字、要纯矢量，都照做；工具只能决定怎么做，不能决定做什么。
- **参考进入判断，不进入画布。** 联网找够、逐张读透、摆出来等一句准话。
- **成品在做它的那个引擎里完成。** 跨引擎只交接文件路径。
- **QA 是硬门槛，但不评判风格。** 0 error（硬伤）+ 局部图看过 + 需求逐条核对。
- **一稿不是稿。** 至少修订一轮、重跑看稿再交（渲染次数只跟"真的改了什么"走，不凑次数）。
- **字形是内容，不是装饰。** 每个变形都要对得上信息与用户的要求。
- **素材要干净。** 能商用、有来源、有署名。
