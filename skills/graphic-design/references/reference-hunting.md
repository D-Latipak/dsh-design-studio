# 找参考：全球互联网都是你的参考库，把「看图」变成设计动作

设计水平的差距，一大半是**参照系**的差距。看得少，就只能做出「居中标题 + 一个色块」。
这份文件管三件事：**去哪找**、**怎么判断找错了**、找到之后怎么把图**变成参数**（而不是照抄）。

配套：**数量门槛 / 全面精读 / 交付过审 / 静默时钟**在 `reference-gate.md`（新稿的硬门槛）；
风格参数按 `style-research.md` 从用户原话现场联网研究得出（本 bundle 没有风格目录）；拿到参考后和参考做 A/B 对比。

> **两条硬规矩**
> 1. **新稿必须先联网找参考**，找够量、逐张读透，**交付给用户过审**（`refs-approved.md`）之后才允许排任何版。
>    流程与门禁见 `reference-gate.md`。
> 2. **来源不限**：全球互联网上任何真实存在的设计/图像都可以当参考——设计站、社交平台、品牌官网、
>    档案馆、旧物照片、影视截图、展览现场……**参考不需要版权**（它不进成品）。
>    只排除"不是设计的东西"（教程截图、模板商店页、水印样机、搜索引擎结果页缩略图、AI 生成图）。

---

## 一、先分清三种参考（用途不同，规矩也不同）

| 类型 | 你要从它身上拿什么 | 例子 | 能不能进成品 |
|---|---|---|---|
| **风格参考**（movement / 时代） | 语法：网格、字号跨度、色数、母题、字距 | 瑞士国际主义海报、波兰海报学派、Risograph 小志 | 不能。只拿参数 |
| **构图参考**（单件结构） | 结构：焦点位置、留白比例、图文比例、边缘处理 | 一张展览海报的上下分区 | 不能 1:1 复刻 |
| **细节参考**（工艺） | 工艺：编号系统、细线、网点、套色错位、纸张 | 高品质海报扫描的高清局部 | 不能描图 |

**硬规矩**：参考图是**研究材料**，不是素材。任何参考图都不得置入成品（`file.place` 只认
`designs/assets/` 里有许可证记录的素材）。版权红线见第八节。

---

## 二、去哪找（来源不限，按"好不好用"排序）

### A. 先 `reference_search`，再决定去哪

**第一步永远是 `reference_search`（本 bundle 的 MCP 工具）**：把检索词放进 `query`，并传 `workspace`
（你的会话工作目录）。它一次完成 Bing 图片搜索（自动剔掉电商/图库/AI 生图/模板站）+ 内置四站 +
任意 `url` 直链 → 下载、质量门槛、去重、拼版，并把这块板记进共享参考库。
要重新联网抓同一块板传 `refresh:true`；想复用以前抓过的板子先用 `reference_library` 查。
只有在工具列表里看不到 `reference_search` 时，才退回 `web_search` + `New-ReferenceBoard.ps1 -Url`。

### B. 脚本内置的四站（方便，不是门槛）

| 来源 | 内容 | 脚本里的 id | 取用 |
|---|---|---|---|
| **Are.na** | 设计师/艺术家公开收藏：海报、版式、字体、编辑设计、当代平面 | `arena`（默认） | 自动检索，1800px 大图，按 block 记来源 |
| **Design Reviewed** | 平面设计史档案：海报、封面、广告、书籍 | `designreviewed`（默认） | 自动检索，原图（常 2560px） |
| **Fonts In Use** | 真实项目的字体使用档案 | `fontsinuse` | 排版/字体专项时用 |
| **It's Nice That** | 当代设计媒体 | `itsnicethat` | 编辑/品牌专项时用 |

### C. 任何网站（`-Url`，覆盖面最大）

| 类别 | 例子 | 备注 |
|---|---|---|
| 作品平台 | Behance / Dribbble / ArtStation / 站酷 / 花瓣 | 反爬就换转载页，别硬爬 |
| 社交与灵感 | Pinterest / Instagram / X / Reddit / Tumblr / 小红书 | 只能拿到主图就够用（看结构不看细节） |
| 品牌与机构 | 品牌官网 / VI 手册 PDF / 博物馆与图书馆数字馆藏 / 出版社官网 | 手册里的规范页信息量极高 |
| 实物与场景 | 旧票据 / 包装 / 招牌 / 街拍 / 展览现场 / 电影截图 | 结构和材质往往比"设计作品集"更真 |
| 其他领域 | 建筑 / 织物 / 陶瓷 / 油画构图 | 只借结构，不借表面 |

### B. 公共馆藏（**兜底，需要显式开启**）

| 来源 | 内容 | 脚本 id | 许可 |
|---|---|---|---|
| Art Institute of Chicago | 19–20 世纪海报、版画 | `aic` | CC0 / 研究用 |
| The Met Open Access | 版画、海报、装饰艺术 | `met` | CC0 |
| Cleveland Museum of Art | 版画、海报、纹样 | `cleveland` | CC0 |
| Wikimedia Commons | 设计史名作、展览照片 | `commons` | 逐件不同 |
| Openverse | 现代摄影、插画、纹理 | `openverse` | CC0 / CC BY 等 |

**为什么默认关闭**：馆藏的关键词检索非常松。实测搜 `constructivist poster`，AIC 返回的是
1917–1918 年的**美国一战宣传海报**（「Buy a Little Present for the Kaiser」）；搜 `swiss style poster`，
Met 返回**瑞士卫队盔甲与佩剑**。它们在字段里确实含关键词，但和「构成主义海报」「瑞士国际主义」
不是一回事。**只有在你明确要历史公有领域原件时**才加 `-Sources aic,met`，并且必须逐张看。

### C. 读文字的设计知识站（用来看「怎么做」，不搬图）

- **Fonts In Use**（fontsinuse.com）：真实项目用了什么字体、字号关系。
- **Design Reviewed**（designreviewed.com）：按年代/地区看海报与封面。
- **AIGA / MoMA / V&A 的展览页**：movement 的准确定义与代表作品。
- **字体厂商博客**（Google Fonts、Adobe Fonts、TypeTogether）：字体搭配与排版细节。
- **Wikipedia**：只在需要「这个运动的时间/主张/代表设计师」时查，别拿它当审美来源。

---

## 三、搜索词怎么写（决定你找到什么）

原则：**movement + medium + decade/region**，三个词一起给，用英文。只搜「海报设计」只会得到图库垃圾。

| 目的 | 好搜索词 | 坏搜索词 |
|---|---|---|
| 找风格语法 | `swiss style poster 1960s`、`soviet constructivist poster` | `海报设计` |
| 找构图 | `exhibition poster layout two column 1960s` | `好看的海报` |
| 找工艺 | `risograph poster two color overprint` | `risograph` |
| 找中文语境 | 先译成英文搜参数（`republican era calendar poster`），再用中文核气质 | `复古风` |
| 找字体搭配 | `editorial spread serif sans pairing` | `字体搭配` |

补充：
- 加年代（`1970s`）、地区（`polish`、`japanese`、`hong kong`）、印刷方式（`letterpress`、`screen print`、`offset`）。
- 想看结构而不是成品，搜 `poster grid analysis`、`layout breakdown`、`case study`。
- 设计师名字往往比风格名更准：`josef muller-brockmann poster` 好过 `swiss style`。
- 风格名也可能有别名：`international typographic style` ≈ `swiss style`。

---

## 四、标准流程（六步，约 15–30 分钟）

> 本节的产物要满足 `reference-gate.md` 的门槛：**≥ 4 张、≥ 2 个来源 / 检索词**（来源不限）。
> 只拿到 2–3 张就急着写 DNA 卡，会被参考关打回。

### 第 1 步：先把用户的话拆成检索式，再找图

把用户原话拆成检索维度（题材/年代/媒介/版式/字体/色彩/氛围/参照物），写成 2 组以上检索词——
**先有用户的话，再有检索式**，不要先想"这是某某流派"。
不要预设一个"风格假设"再去凑图：假设是查完之后的结论。边搜边收窄，觉得跑偏就换词。
用户点名了参考物（作品/设计师/品牌/年代/网站），优先直接找那个东西。

### 第 2 步：抓一张参考板（首选 `reference_search`）

```text
reference_search({
  query: ["soviet constructivist poster", "swiss style poster 1960s"],
  workspace: "<你的会话工作目录绝对路径>",
  max: 12, minWidth: 1200
})
```

返回 `count / bySource / items / board / warnings`，板子在 `designs/references/<slug>/`。
同一组检索词再调一次会直接命中缓存（`cached: true`）；要重新联网抓传 `refresh: true`。
需要喂指定页面/直链时加 `url: ["https://…","https://…"]`。

没有 MCP 工具时退回脚本：

```powershell
$skill = "C:\Users\<you>\.dsh\bundles\design-studio\skills\graphic-design"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\New-ReferenceBoard.ps1" `
  -Query "soviet constructivist poster" -Slug constructivist-ref -Limit 4
```

内置源默认 = `arena|designreviewed`；其他平台用 `-Url` 喂页面或图片直链。常用变体：

```powershell
# 排版/字体专项：加 Fonts In Use
-Sources "arena|fontsinuse"

# 当代编辑设计/品牌：加 It's Nice That
-Sources "arena|designreviewed|itsnicethat"

# 明确要历史公有领域原件：才开馆藏（结果必须逐张核年代与媒介）
-Sources "arena|aic|met" -MinWidth 1000

# 用 web_search 找到的任意页面（Behance/站酷/Pinterest/品牌站/档案馆…）或图片直链
-Url "https://www.behance.net/gallery/xxx","https://fontsinuse.com/uses/59656/xxx"
```

> `-Query` / `-Sources` / `-Labels` 的多个值用 `|` 或 `;` 分隔（`-File` 调用传不了数组字面量）。

产物（默认在 `<工作区>\designs\references\<slug>\`）：

```
designs/references/swiss-ref/
  board.png        ← 拼版图，直接 read_image
  refs.json        ← 来源/作者/年代/许可/尺寸/类型（design 或 museum）
  REFS.md          ← 人读清单
  img/01.jpg …
```

脚本内置质量门槛：**宽 ≥ 1200px、文件 ≥ 20KB、能正常解码**；达不到的下载后直接丢弃并在
`warnings` 里说明。没有大图但有对的图时，用 `-MinWidth 1000` 放宽（要在交付说明里注明）。
**宁可板子上只有 3 张对的，也不要 12 张错的。**

### 第 3 步：先判断「对不对」，再看「好不好」

打开 `board.png` 看整体，再逐张 `read_image`。**四种「不对」的信号，命中任何一条就换图/换词**：

1. **年代不对**：说 1920s 构成主义，结果是一战美国征兵海报。
2. **媒介不对**：说海报，结果是照片、室内陈设、网页截图、教程界面。
3. **类别不对**：说平面设计，结果是器物、织物、盔甲、珠宝（馆藏源高发）。
4. **来源不对**：图库水印、Pinterest 缩略图、教程截图、AI 生成图。

板子里 2–3 张同一语法的留下来写 DNA 卡，其余当「反例」；**来源不对或年代不对的直接删掉，
不要凑数**。如果整板都不对：换更具体的关键词（movement + medium + decade），或用 `-Url`
从你确认过的专业页面取图，不要勉强用。

### 第 3.5 步：逐张精读（全面学习参考图，别只看缩略）

**每一张留在板子上的图都要读成参数**，写进 `designs/<slug>/reference-study.md`。
**7 条**：语法定位 / 网格与比例 / 层级与字号跨度 / 字体与图文关系 / 色彩 / 母题与工艺（+ 节奏）/
可迁移与不学（可迁移 2 条 + 不学 2 件 + 对应 R0N）。完整模板与完成度自检见
`reference-gate.md` 第三、四节（**那份文件是唯一事实源**）。

- 先 `read_image` 看 `board.png`，再逐张看 `img/NN`；标题区 / 信息区要放大看（拼 2× 或裁切）；
- 数字能估就估（4.8× 字号跨度、45% 留白、3 色），估不出写「看不清」——**不许编**；
- 全板做一次交叉分析：3 条共性 + 3 条差异 + 1 条「两个参考打架时选谁」；
- 精读没做完，DNA 卡不许开写。

### 第 4 步：写「风格 DNA 卡」（10 个字段，必须落字，每字段带溯源）

```markdown
### 风格 DNA：<风格名> × <本次用途>
1. 参照：#01 <来源 1 标题/作者/年代>、#03、#04
2. 网格：12 栏 / 栏距 4mm / 版心 62×800pt / 元素只贴 3 条栏线（#01）
3. 焦点：主标题压在左上第 1–6 栏、基线 y≈240；面积占 22%（#03）
4. 字号跨度：主 132pt / 副 26pt / 正文 10.5pt（比 5.1×）（#01 #04）
5. 色彩：4 色（#0E1B2A / #F2E8D5 / #E2603C / #7BB51C），强调色只出现 2 次（#03）
6. 字体：标题 Noto Serif SC + Inter；正文 Noto Sans SC；标题字距 -25（#01）
7. 母题：8pt 橙色横线、右下角编号 01–04、圆点标记（#04）
8. 肌理：无（纯色块）；照片统一降饱和 20%（#01 #04）
9. 节奏：大留白（≥45%）→ 密集信息块（底部 120pt）→ 一条线收口（#03）
10. 我不抄的 3 件事：<#01 的某个具体处理>、<#03 的……>、<#04 的……>
```

**每个字段后面必须跟 `#NN` 溯源**：说不出是哪张图给你的，这个字段就是自己编的，删掉或补查。
DNA 卡的用途：它是**设计决策单的上一级**。后面所有命令参数都从这里推，不是临场发挥。

### 第 5 步：只把 3 条「可迁移规则」写进设计决策单

DNA 卡是研究，决策单是承诺。决策单里只保留：
1. 一条结构规则（网格 / 分区 / 焦点）
2. 一条对比规则（字号跨度 / 明暗 / 疏密）
3. 一条识别规则（母题 / 色彩 / 字体性格）

其余留在 DNA 卡里。**参考是约束，不是装饰清单。**
出稿后和参考做 A/B 对比，只学「它做了我没做的 3 件事」，并把用户明确要的部分放在第一位。

### 第 6 步：交付说明里如实写参考

交付说明写 2 句：「参考了 <movement> 的 <网格/字号跨度/母题>，没有使用任何参考图的图像内容」。
使用了当代设计师作品做研究，就点名，不要装作原创。

---

## 五、参考板怎么存、怎么复用

- 目录：`designs/references/<slug>/`，`slug` 用项目名或风格名（`swiss-ref`、`hk-neon-ref`）。
- 每块板子都要有 `refs.json` + `REFS.md`。**没有记录的图等于没有参考。**
- 同一项目反复用同一块板子时，在 `REFS.md` 末尾追加一行「本次从这块板子拿了：……」。
- 板子可以跨项目复用（`designs/references/` 是共享库），但**每次都要重新看**，不要凭记忆。
- 板子里的图如果后来发现不对，删掉 `img/` 里的文件和 `refs.json` 对应条目，重跑拼版
  （或换 slug 重建）；不要留着错的图给下一稿用。

---

## 六、联网失败 / 只有内网时

联网找参考是新稿的**默认硬门槛**（`reference-gate.md` 第九节）。失败也不能静默跳过：

1. 先跑环境自检：`reference_status`（MCP 工具，一次报出 Bing 图搜 / Are.na / Design Reviewed /
   Fonts In Use / It's Nice That 的连通性）；没有这个工具时用
   `Invoke-WebRequest -Uri "https://api.are.na/v2/search?q=bauhaus&type=Image" -UseBasicParsing -TimeoutSec 15`。
2. 失败先**重试**：换来源（designreviewed / fontsinuse / itsnicethat）、换关键词、改用 `-Url`，最多 3 轮。
3. 仍失败才降级，而且**必须摆到过审消息里**让用户知情：
   - 复用 `designs/references/` 里已有的板子（先 `read_image` 再看，别凭记忆）；
   - 用你的专业判断当「文字化参考」（写进决策单，方便用户推翻）；
   - 用用户提供的图 / `designs/assets/` 已有素材。
4. 在 【参考过审】消息和交付说明里写明「**本次联网失败**，用的是已有参考板 / 你的判断」，
   由用户决定：等网络恢复、还是接受降级继续。
5. **禁止**：凭印象编造「我参考了某张名作」；把 AI 生成的图说成参考图；把失败藏起来假装找过。

`refs.json` 里的 `designCount` 只是统计字段，**不再是门槛**：全部来自馆藏、全部来自 Instagram、
全部来自旧书扫描，只要画面真的对得上需求，都可以过审。

---

## 七、和「找素材」的区别（别混）

| | 参考（reference） | 素材（asset） |
|---|---|---|
| 目的 | 学语法、定参数 | 放进成品 |
| 存放 | `designs/references/<slug>/` | `designs/assets/` |
| 来源 | 全球互联网，任何真实设计/图像（不限站点） | 开放素材源（CC0/PD/CC BY…） |
| 许可 | **不需要**（不进成品）；但记录来源以示出处 | 必须 CC0/PD/CC BY/BY-SA/MIT/ISC/Apache/OFL，写 `manifest.json` + `CREDITS.md` |
| 能否进版面 | 绝不能 | 可以，且必须署名合规 |
| 脚本 | `New-ReferenceBoard.ps1` | `Fetch-FreeAsset.ps1` |

一句话：**参考进入你的判断，素材进入你的画布。两者永远不混。**

---

## 八、版权红线（写死）

1. 不 1:1 复刻任何单件作品：布局、配色、图形组合至少改 3 个维度，且改动要写进交付说明。
2. 不描图、不临摹插画、不把别人的 logo/字体当自己的。
3. 不把参考图置入成品、不把参考图当素材打包进交付物。**但必须把编号参考板作为「过审件」发给用户看**
   （`reference-gate.md` 第五节）——这是研究沟通，不是素材交付。
4. 当代设计师作品只用于研究；要「致敬」就在交付说明里点名，不要装作原创。
5. 商业字体、图库水印图、来源不明的「免费下载」一律不碰。
6. 参考记录里保留原始链接与作者名——这是研究者的基本礼貌，也是出事时唯一能自证的东西。
