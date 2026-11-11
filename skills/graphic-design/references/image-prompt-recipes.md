---
name: image-prompt-recipes
description: AI 生图提示词的取材与改写配方——先查索引再只开一个模板，把 gpt-image-2 的结构化提示词压成 z-image-turbo 吃得下的短提示词，并强制「画面文字一律归排版层」。
applies_to: generate_image / edit_image 出底图与局部图
library: references/image-prompt-templates/（17 类 / 93 个模板 + 总规范 prompt-writing.md）
source: https://github.com/ConardLi/garden-skills（skills/gpt-image-2 @ 2b9a893，MIT）
last_updated: 2026-11-06
---

# AI 生图提示词配方

## 一分钟版

1. **底图只出「画面」，不出「版面」**——画面里不写字，字全部留给排版层（第 6 节，硬规则）。
2. 按第 3 节的表选**一个**类别 → 只打开**一个**模板文件 → 读完就关。
3. 按第 4 节把模板压成 **20–60 个英文词**的一段话，再用 `generate_image`。
4. 模板给的是「该画什么、怎么分区、什么光、什么色」，**不是**让你照抄它里面的标题、claim、UI 文案。

---

## 一、这套模板库是什么，又不是什么

`references/image-prompt-templates/` 是从 `ConardLi/garden-skills` 的 `gpt-image-2` skill 整包 vendor 进来的提示词模板库：

- `prompt-writing.md` —— 总规范：模板怎么组织、字段怎么分「必问 / 默认 / 随机」、缺信息怎么问。
- 17 个分类目录 / 93 个单模板（每个 2.9–15 KB，平均 8 KB），含 8 类画面、5 类编辑工作流、4 类结构图。
- `MANIFEST.json` —— 本库的索引（分类、文件名、字节数、上游 commit），比人肉 `ls` 快。
- `LICENSE-garden-skills.txt` —— 上游 MIT 原文，必须跟着走。

**它不负责出图。** 出图工具、落盘、水印、分辨率、shim 拓扑一律看 `references/assets-generation.md`。
**也不是每张图都要过模板**：单主体、纯氛围、抽象底图，直接按 assets-generation 的要素表写 20–60 字更快。

---

## 二、上下文规则：先读索引，再只读一个模板

这是本库唯一的「使用方法」，违反它的代价是上下文被吃掉：

1. **先读索引** —— 第 3 节的表，或 `MANIFEST.json`。目的只是选一个类别。
2. **再打开恰好一个模板文件** —— 挑该目录里最贴近当前任务的那一个。模板之间互相引用（「不要使用：用 xxx.md」），顺着引用跳一次可以，跳三次说明选错了。
3. **不要整目录读** —— 93 个文件合计约 750 KB，全塞进来是十万级 token。一次只开一个，读完提取完就丢掉原文。
4. **只提取四样东西**：① 画面必须出现的元素清单 ② 分区 / 版面骨架 ③ 光线与质感词 ④ 色板与约束。然后按第 4 节改写。
5. **`prompt-writing.md` 只在要自己造新模板时读**，日常出图不需要。

> 一个任务一个模板。要出「一组」图（同一 campaign 的 6 个版位），也先按一个模板定 DNA，其余版位只改比例和留白。

---

## 三、分类速查：什么时候开哪个

| 目录 | 模板数 | 什么时候开 | 代表文件 |
| --- | --- | --- | --- |
| `poster-and-campaigns/` | 8 | 海报、KV、campaign 主视觉、杂志封面、系列 lineup | `campaign-kv.md`、`brand-poster.md`、`editorial-cover.md` |
| `branding-and-packaging/` | 6 | 品牌板、包装、标签、吉祥物、周边、角色 merch | `brand-identity-board.md`、`cosmetic-packaging.md` |
| `product-visuals/` | 6 | 电商主图、白底图、场景图、爆炸图、包装展示 | `white-background-product.md`、`exploded-view-poster.md` |
| `infographics/` | 6 | 信息图、KPI 面板、分步说明、bento 版式 | `bento-grid-infographic.md`、`step-by-step-infographic.md` |
| `technical-diagrams/` | 7 | 架构图、流程图、时序图、ER、状态机、拓扑、思维导图 | `system-architecture.md`、`flowchart-decision.md` |
| `typography-and-text-layout/` | 2 | 「文字本身就是画面」的版式（仍按第 6 节交给排版层实现） | `title-safe-poster.md`、`bilingual-layout-visual.md` |
| `editing-workflows/` | 5 | 已有图要改：换背景、去物、换局部对象、修图、人像局部 | `object-removal.md`、`background-replacement.md` |
| `academic-figures/` | 9 | 论文式机制图、方法管线、对比网格、科研海报 | `mechanism-diagram.md`、`graphical-abstract.md` |
| `ui-mockups/` | 6 | 界面样机、落地页、直播间、商品卡、短视频封面 | `social-interface-mockup.md`、`live-commerce-ui.md` |
| `grids-and-collages/` | 5 | 多宫格、拼贴、lookbook、banner 矩阵 | `banner-grid-2x2.md`、`lookbook-grid.md` |
| `storyboards-and-sequences/` | 8 | 分镜、漫画、动画 KV、流程照片板、人物关系图 | `cinematic-storyboard-grid.md`、`four-panel-comic.md` |
| `maps/` | 5 | 插画地图、美食地图、行程图、门店分布、路线图 | `illustrated-city-map.md`、`food-map.md` |
| `scenes-and-illustrations/` | 4 | 概念场景、治愈场景、极简氛围、绘本 | `minimalist-mood-scene.md`、`concept-scene.md` |
| `portraits-and-characters/` | 5 | 人物设定、创始人肖像、姿势参考、虚拟主播 | `character-sheet.md`、`professional-portrait.md` |
| `avatars-and-profile/` | 5 | 头像、贴纸、3D 图标、风格迁移自拍 | `sticker-set.md`、`themed-3d-icon.md` |
| `slides-and-visual-docs/` | 4 | 讲解型 slides、教学图页、报告页 | `dense-explainer-slides.md`、`visual-report-page.md` |
| `assets-and-props/` | 2 | 游戏画面样机、拟物图标套装 | `retro-skeuomorphic-icons.md`、`game-screenshot-mockup.md` |

选不出来就退回 `assets-generation.md` 的要素表手写提示词——比硬套一个不合适的模板好。

---

## 四、从 gpt-image-2 到 z-image-turbo：五步压缩

gpt-image-2 的模板是为「能读长结构化 JSON 的模型」写的；本机是 **8 步蒸馏的 `z-image-turbo`**，对**短而具体**的提示词更稳。照抄模板 = 效果变差 + 烧时间。压法：

1. **结构拍平**：模板的 `sections / layout / grid` 全部翻译成一句「谁在画面哪里、占多少」。只保留 3–5 个视觉要素。
2. **删掉所有文字诉求**：`headline / claim / title / caption / UI copy / price tag` 一律删，改成「对应位置留空」。见第 6 节。
3. **压到 20–60 个英文词**（中文 40–120 字）。超了就继续删形容词，先删背景故事，再删次要元素。
4. **换掉会触发乱码的词**：实测 `poster / 日式 / 标题 / 字体 / 汉字` 会让 Z-Image 自己「发明」假字。改写成**材质 / 色场 / 光线 / 构图**的说法。
5. **补三条尾巴**：比例（交给 `size` 参数）、`no text, no typography, no letters, no watermark`、以及留白位置（例如 `ample empty space at the top`）。

### 改写示例

模板 `poster-and-campaigns/campaign-kv.md` 里那种三段式（anchor visual + layout system + claim 区）压完是：

**压前（模板语义）**：季度 campaign 主视觉；左侧 60% 为产品 anchor；右侧 40% 为 claim 区与色块；品牌色 #0E1B2A + 强调色 #E4572E；硬光、长阴影；需延展到 banner / story。

**压后（可直接 `generate_image`）**：

```text
product still life, single hero object at left third, deep navy backdrop,
one strong vermilion rim light, long hard shadow, matte studio floor,
generous empty space on the right for type, graphic and minimal,
no text, no typography, no letters, no watermark
```

要点：留白说成「empty space on the right」而不是「right side is the title area」；色值用英文色名或直接 hex（`#0E1B2A`）；镜头/光线词照抄模板是安全的，版面词不是。

### 参数对照

| 模板里的字段 | 本机怎么给 |
| --- | --- |
| `aspect_ratio` / `size` | `generate_image.size`：`1:1`、`16:9`、`9:16`、`4:3` |
| `resolution` / `quality` | `quality: 1k / 2k`；本地短边 1024，印刷大图别指望 |
| `variants` / `n` | `count: 1–4`，一张 20–40s，别一次开 4 张试错 |
| `text / copy` 字段 | **丢弃**，交给排版层 |
| `negative_prompt` | 合并进正向句尾：`no text, no typography, no watermark` |

---

## 五、图生图（`editing-workflows/`）怎么落地

5 个模板对应 `edit_image`，但本机走 shim（strength 固定 **0.6**），能力边界必须先说清：

- ✅ **擅长**：加元素、换局部内容、去小物件——「保持构图 / 留白 / 配色不变，把 X 换成 Y」。
- ⚠️ **不擅长**：整幅换色调（底图颜色强时几乎改不动）。**调色一律交给 PhotoCraft**（levels / curves / colorBalance）。
- 提示词同样压短：一句「改什么 + 保持什么」即可，不要搬模板的十段式。
- 尺寸受 shim 限制（总像素 ≤ 1536×1024），大图需求按 `assets-generation.md` 的回退方案。

```text
keep composition, framing and palette unchanged; remove the small object
at bottom right, fill with the surrounding background; no text, no watermark
```

---

## 六、硬覆盖：画面里的字，一律归排版层

**这条覆盖模板里的一切文字字段，没有例外。**

- 即使模板写了 `headline`、`claim`、`caption`、`price`、`标签文字`、`双语版式`，**也不许**把这些词写进生图提示词。
- 底图提示词固定收尾：`no text, no typography, no letters, no watermark`。
- 模板里「文字区」只能翻译成**留白**：`ample empty space at the top`、`clean right margin`。
- 出图后必须 `read_image` 自查有没有假字 / 乱码汉字假名；**带假字的图不许进成品**，换更抽象的提示词或裁掉。
- 所有真实文字用排版层（DesignCraft / VectorCraft + `assets/fonts/` 里的 OFL 字体）真排：这样字可读、可改、可校对，也不会被模型写坏。

原因很实在：本地蒸馏模型写不好文字，宁可留白也不要「看起来像字的乱码」。
`typography-and-text-layout/` 两个模板的价值在于**版式骨架**（标题安全区、双语层级），骨架交给排版层实现，不是让模型画字。

---

## 七、复用与合规

- 上游：`https://github.com/ConardLi/garden-skills` → `skills/gpt-image-2/references`，commit `2b9a89340b70f632d31c0f1c69fce94a7912423e`，许可 **MIT**。原文见同目录 `LICENSE-garden-skills.txt`。
- **不改名、不重组目录**：文件与分类名和上游保持一致，升级时按目录整包替换即可；新增本地的模板另起文件名，别覆盖上游同名文件。
- 不 vendor `scripts/`（上游的 `generate.js` / `edit.js` 走 OpenAI 接口，本机用 `generate_image`，不需要）。
- 引用这些模板写交付说明时附一句：`提示词模板改编自 ConardLi/garden-skills（MIT）`。
- 本库所有示例提示词的最终解释权在 `assets-generation.md` 的实测约束——两者冲突时以实测为准。
