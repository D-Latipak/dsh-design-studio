# 免费素材源与取用规矩（2026-10-30 实测）

一句话：**缺素材不要凑合，去按许可证取真素材；每份素材都要有账。** 照片/插画/纹理/图标先在这里找，找不到再生图，最后才自绘 SVG。

本文件里的接口、脚本、许可证判断都在本机（Windows PowerShell 5.1 + 直连网络）跑过，
「实测」一列就是当时的证据。换机器/换网络后先跑一次 `Fetch-FreeAsset.ps1` 再信它。

---

## 0. 在素材关里的位置（取材顺序第 3 站）

素材关（`material-pass.md`）是每单必做的关，取材顺序固定为：

```
用户素材 → designs/assets/ 已有 → 免费素材站（本文件）→ AI 生图 → 自绘矢量（只做字/图标/几何/纹样）→ 占位
```

本文件就是**第 3 站**。什么时候停在这里、什么时候往下沉，看三条：**主题对得上 / 分辨率够 / 许可干净**——
三条都满足就用现成素材，缺一条才降到 AI 生图，别一上来就生图，也别为了「有素材」硬凑一张跑题的。

分工别串：本文件管**源、许可、抓取、记账**（§1 许可表、§2 源清单、§3 脚本、§6 CREDITS）；
`material-pass.md` 管**取材顺序、编号、素材板、联动做法**。取到图之后必须回素材关：编号进
`material-plan.md`、拼进 `materials-board.png`、过一遍 PhotoCraft 再置入——**下载完不等于素材关做完**。

---

## 1. 许可速查（决定用不用，先查这张表）

| 许可 | 可商用 | 可改 | 必须署名 | 结论 |
|---|---|---|---|---|
| **CC0 / 公有领域（PD / PDM）** | 是 | 是 | 否 | 首选，爱怎么改怎么改 |
| **CC BY** | 是 | 是 | **是**（作者 + 许可 + 来源链接） | 可用，署名必须落到成品或说明里 |
| **CC BY-SA** | 是 | 是 | **是**，且衍生作品要同许可发布 | 商业稿默认避开（客户通常不接受"海报也得 CC BY-SA"） |
| CC BY-NC / CC BY-NC-SA | 否 | 是 | — | **不用**（禁商用） |
| CC BY-ND | 是 | **否** | — | **不用**（裁切/调色都算演绎） |
| OFL / Apache-2.0 / MIT / ISC（字体、图标） | 是 | 是 | 保留版权声明 | 字体/图标首选；不能把文件本身拿去卖 |
| Unsplash / Pexels / Pixabay 自有许可 | 是 | 是 | 不强制（建议署名） | 可用；不得转售原图、不得用可识别的人/物暗示背书 |
| NASA（美国政府作品） | 是 | 是 | 不强制 | 但**不是 CC0**；封面/广告/周边需 clearance，NASA logo 不能当装饰 |
| 「免费字体下载」站二次打包 / 图库水印图 / 来源不明 | — | — | — | **不用**。商业字族（汉仪/方正/站酷…）除非官方明确免费商用并给出许可页 |

判断不了就当没有许可。用户坚持要用，让他自己确认来源；确认不了就换素材或改纯排版。

---

## 2. 源清单（每一条都在本机跑过）

**什么时候用哪个**：材质纹理 → Poly Haven；历史画作/版画/纹样 → Cleveland / Met / Commons；
现代摄影 → Openverse（挑 `provider=wikimedia` 的条目）；图标 → Iconify；太空/科学 → NASA；器物/艺术 → Cleveland + Met（Smithsonian 要 key）。

### 2.1 免 key、脚本内建

| 源 | 拿什么 | 许可 | 检索 / 下载 | 实测（2026-10-30） |
|---|---|---|---|---|
| **Cleveland Museum of Art** | CC0 艺术品，一件给 web / print / full 三档 | CC0（`share_license_status`） | `openaccess-api.clevelandart.org/api/artworks/?q=<kw>&cc0=1&has_image=1&limit=20` → `data[].images.print.url` | ✅ print 2599×3400 / 5.4 MB；一条 JSON 三档、元数据尺寸零误差 —— **艺术类首选** |
| **The Met Open Access** | 世界名画高清 | CC0 | `…/public/collection/v1.1/search?hasImages=true&offset=0&limit=50&q=<kw>` → `…/v1/objects/{id}` → `primaryImage` | ✅《神奈川沖浪裏》3859×2594 |
| **Wikimedia Commons** | 历史照片、文物、地图、纹样 | 条目自带（多为 PD / CC BY-SA） | `…/w/api.php?action=query&format=json&generator=search&gsrsearch=<kw>+filetype:bitmap&gsrnamespace=6&gsrlimit=6&prop=imageinfo&iiprop=url\|size\|extmetadata&iiurlwidth=1920`<br>一步下原图：`commons.wikimedia.org/wiki/Special:FilePath/<文件名>?width=1920` | ✅ 1920×1291（thumb）、3859×2594（真原图） |
| **Poly Haven** | 纸/织物/木/水泥/石材纹理、HDRI 环境 | CC0 | `api.polyhaven.com/assets?t=textures` → `/files/<id>` → `Diffuse.<1k\|2k>.jpg.url` | ✅ 1024²、2048² |
| **Openverse** | 现代摄影（Flickr / 博物馆聚合） | `license=` 硬过滤 | `api.openverse.org/v1/images/?q=<kw>&license=cc0,pdm,by,by-sa&extension=jpg,png&page_size=<≤20>` | ⚠️ 能用但**慢且硬限流**：`page_size≤20`、翻页深度≤240；突发约 20 次要冷却约 5 分钟；`/thumb/`、`/v1/images/{id}/` 对匿名 500；`url` 常是 960w 缩略图（元数据却自称 6016×4016） |
| **Iconify** | 图标（200+ 图标集） | **按 prefix 变**：lucide=**ISC**、mdi / carbon / material-symbols=Apache-2.0、tabler / heroicons / ph=MIT、simple-icons=CC0 | 搜索 `…/search?query=<kw>&prefix=<set>&limit=8`；下载 `…/<set>/<name>.svg?height=1024&color=%23RRGGBB`（**默认 `1em`+`currentColor`，不传参落版会很小且是黑色**） | ✅ 200；`/collections?prefix=` 查该集许可 |
| **google/fonts（GitHub raw）** | 全量 Google Fonts 字体 | OFL / Apache-2.0 | `raw.githubusercontent.com/google/fonts/main/ofl/<family>/<File>.ttf` | ✅（细节见 §5） |
| **NASA Image Library** | 太空 / 地球 / 科学 | 美国政府作品**不受版权保护，但不是 CC0** | `images-api.nasa.gov/search?q=<kw>&media_type=image` → `images-assets.nasa.gov/image/<id>/<id>~orig.jpg` | ✅ 2880×1800；`~large` 不是每张都有（会 403）；封面/广告/周边需 clearance |
| **Fontshare（ITF）** | 商用免费字体 | ITF FFL（**不是 OFL**） | `api.fontshare.com/v2/fonts`（详情要 **UUID**，传 slug → `invalid_uuid`）；zip `/v2/fonts/download/<slug>` | ✅ 200 / 每页 100 条；无中文字族 |

**图标集黑名单（脚本直接拒绝）**：GPL 的 `wordpress / gridicons / dashicons / icomoon-free / et / gala`；CC BY-NC 的 `ps / cbi`。

### 2.2 要 API key 的（值不值得看项目）

| 源 | 许可 | 申请 + 调用 | 现状 |
|---|---|---|---|
| **Unsplash** | Unsplash License（**不在白名单 6 种里**，只在客户明确要"图库级商业摄影"时考虑） | https://unsplash.com/developers （demo 50 req/h，过审 1000 req/h）<br>`GET api.unsplash.com/search/photos?query=<kw>&client_id=<KEY>` | 无 key → 401 `OAuth error: The access token is invalid` |
| **Pexels** | Pexels License | https://www.pexels.com/api/ ，`GET api.pexels.com/v1/search?query=<kw>`，头 `Authorization: <key>` | 无 key → 401 `Missing API key`；文档页被 Cloudflare 403，额度未能证实 |
| **Pixabay** | Pixabay Content License | https://pixabay.com/api/docs/ （100 req/60 s），`GET pixabay.com/api/?key=<KEY>&q=<kw>` | 无 key → 400 `Invalid or missing API key` |
| **Smithsonian Open Access** | CC0（器物/艺术，本该是最好的一档） | `GET api.si.edu/openaccess/api/v1.0/search?q=<kw>&api_key=<KEY>` | 403 `API_KEY_MISSING` —— 没 key 完全用不了 |

> 日常够用，不必申请：现代摄影走 Openverse（挑 wikimedia 条目），艺术/器物走 Cleveland + Met，历史影像走 Commons，底纹走 Poly Haven，图标走 Iconify，字体走 google/fonts。

### 2.3 实测不可用 / 不许用

| 源 | 现象 | 结论 |
|---|---|---|
| Art Institute of Chicago | 403 Cloudflare `Just a moment...` | 本机 IP 被挑战页挡住，**不可用** |
| `source.unsplash.com` | 503 `Application Error` | 已下线，别再引用 |
| Lorem Picsum | 200 但**没有逐张许可与作者字段**（EXIF 只有 Picsum ID） | 只当占位图，**商业稿不许用** |
| 「免费字体下载」站二次打包、图库水印图、来源不明 | — | 一律不用（见 §1） |

---

## 3. 抓取流程（`scripts/Fetch-FreeAsset.ps1`）

本机 PowerShell 执行策略禁止直接跑 `.ps1`，**一律这样调**（不要去改系统执行策略）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<工作区>\design-studio\skills\graphic-design\scripts\Fetch-FreeAsset.ps1" <参数>
```

| 参数 | 说明 |
|---|---|
| `-Source` | `openverse` / `wikimedia` / `met` / `cleveland` / `polyhaven` / `iconify` / `url` |
| `-Query` | 检索词；英文命中率更高 |
| `-Limit` | 最多落盘几个（默认 3） |
| `-MinWidth` | 最小像素宽（默认 1200）；印刷稿按需提到 1600–2400。**按下载后的实测像素筛，不信 API 自称的尺寸** |
| `-Dest` | 落盘目录。默认 `designs/assets`；单项目建议 `designs/<slug>/assets` |
| `-Set` | `iconify` 的图标集前缀（默认 `lucide`；黑名单见 §2.1） |
| `-Role` | `photo` / `icon` / `texture` / `artwork` / `font` / `graphic`，写进账本 |
| `-AllowAnyLicense` | 越过许可门槛（记录里带 `licenseRisk=true`，交付时必须向用户说明） |
| `-DryRun` | 只下载不记账（探路用） |

`-Source url` 是给「已知直链」用的，**必须**同时给 `-License`，否则脚本拒绝下载（没有账本的素材不许进版面）：

```powershell
# 例：思源宋体（变量字体，OFL）
... Fetch-FreeAsset.ps1 -Source url `
    -Url "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf" `
    -License "OFL-1.1" -Creator "Google / Adobe" -Role font `
    -LandingUrl "https://fonts.google.com/noto/specimen/Noto+Serif+SC" -Dest "designs\assets\fonts"
```

跑完会在 `-Dest` 里留下三样东西：

```
designs/assets/
├─ wood-photo-093012-1.jpg        下载来的素材（文件名带时间戳与序号，不覆盖已有文件）
├─ manifest.json                  账本：来源/作者/许可/许可链接/来源页/直链/sha256/宽高/字节/抓取时间
└─ CREDITS.md                     自动生成的署名页（分「需署名」「无需署名」两栏）
```

脚本内建的许可门槛：NC / ND / 来源不明的条目直接跳过并打印原因；`-MinWidth` 不足、下载失败、格式不适合排版（tif/zip）也跳过并记原因。

---

## 4. SVG 图标 → 版面能用的 PNG（`scripts/Rasterize-Svg.ps1`）

DesignCraft 的 `file.place` **能吃 SVG**（2026-10-30 复测：A4 里置 400pt，导出 4× 后边缘比 2048px PNG 更锐），
但它内部会把 SVG 转成**位图资源**（`inspect_document` 里是 `kind:"<image>"`，按导出分辨率栅格化），
不是可无限放大的矢量对象；小图标/无明确尺寸（`width="1em"`）的 SVG 会按内在尺寸引入，必须先生成够大的 PNG。
PhotoCraft 打开 SVG 按内在 `width/height` 栅格化（实测 900×900 的 SVG → 900×900 位图；24×24 图标就只有 24px 级）。
所以：**图标类一律先光栅化到目标像素**，自写的大尺寸 SVG 可以直接 `file.place`。

```powershell
... Rasterize-Svg.ps1 -Path "designs\assets\lucide-coffee.svg" -Size 2048 -Out "designs\assets\png" -Color "#F2E8D5" -Background transparent
```

- 实现：Edge `--headless=new` 截图 + 内嵌 base64 SVG 的临时 HTML，尺寸精确到像素，输出 **RGBA 透明 PNG**（实测 1024×1024 colorType=6）。
- `-Size` 按版面算：图标在版面上宽 `pt × 4.1667`，取大不取小。
- `-Color` 把 SVG 里的 `currentColor`/`#000000` 换成指定色（图标跟着版面配色走）。
- `-Pad 0.08` 给图标留 8% 安全边。

---

## 5. 字体：下载 → 装进用户目录 → 在 DesignCraft 里用起来

### 5.1 从哪拿（两条通道，都实测过）

| 要什么 | 通道 | 实测 |
|---|---|---|
| 单个静态字重（西文） | `https://fonts.googleapis.com/css2?family=Inter:wght@400`，UA 设 `curl/8.4.0`，从返回里取 `url(https://…)` 直链 | 200，326,468 B 的 .ttf |
| **变量字体**（一文件多字重） | 只能走仓库：`https://raw.githubusercontent.com/google/fonts/main/ofl/<family>/<Family>[<axis>].ttf` | `fonts.googleapis.com/css2` **永远只给静态实例**（请求 `wght@200..800` 会返回 7 个各自独立的静态 TTF） |
| 中文字体 | 思源黑/宋 = google/fonts `ofl/notosanssc` \| `ofl/notoserifsc`；得意黑、霞鹜文楷 = GitHub Releases | 得意黑 `.otf` 2,003,884 B（CFF）；霞鹜文楷 `.ttf` 25,928,940 B（glyf） |
| Fontshare（ITF） | `GET api.fontshare.com/v2/fonts`（无 key，返回 UUID）；详情必须用 **UUID**；zip：`/v2/fonts/download/<slug>` | zip 内含 OTF+TTF+woff2+`License/FFL.txt`；许可是 **ITF 自有 EULA（不是 OFL）**；**没有中文字族** |

可商用中文字族（认这些）：思源黑体 Noto Sans SC / 思源宋体 Noto Serif SC / 得意黑 Smiley Sans / 霞鹜文楷 LXGW WenKai（均 OFL-1.1）。
西文：Inter、Source Serif 4、Manrope（OFL）、Fontshare 的 Satoshi / Clash Display（ITF FFL）、IBM Plex（OFL）。
**汉仪/方正/站酷等商业字族一律不碰**，除非官方明确免费商用且你能给出许可页。

> 两个"许可 + 覆盖"陷阱：① 霞鹜文楷的 OFL 带附加条款——**子集化/转格式的改版不得再作为桌面可安装字体分发**（直接装官方 TTF 没问题）；
> ② 得意黑只有 9497 字，缺字如 `U+9C49 鳖`，别拿它当正文字体（霞鹜文楷 47336 字、思源黑 30796 字，覆盖够）。

### 5.2 安装（用户级，免管理员）

```powershell
... Install-UserFont.ps1 -Path "designs\assets\fonts\SmileySans-Oblique.otf"
# 看装了哪些 / 卸掉
... Install-UserFont.ps1 -List
... Install-UserFont.ps1 -Uninstall "SmileySans-Oblique.otf"
```

脚本做的事：校验字体骨架（ttf/otf/ttc，拒绝 woff/woff2）→ 拷到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
→ 在 `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts` 登记 → `AddFontResourceW` + 广播 `WM_FONTCHANGE`
→ 用 `System.Drawing` 回读家族名，告诉你 DesignCraft 里该写哪个名字。

### 5.3 在 DesignCraft 里认出来（这一步最容易想当然）

**家族名以 `font.list` 为准，别抄 Windows 字体列表。** DesignCraft 用 typographic name，Windows/GDI 用中文名或把字重拆成独立家族：

| DesignCraft 里写这个 | Windows/GDI 显示 | 来源 |
|---|---|---|
| `Noto Sans SC` | Noto Sans SC | installed（系统预装，**不是**本次安装） |
| `Smiley Sans` + `fontStyle:"Oblique"` | 得意黑 | installed（CFF/OTF） |
| `LXGW WenKai` | 霞鹜文楷 | installed（TTF） |
| `Manrope` + `fontStyle:"Light" / "Regular" / "Bold"` | Manrope / Manrope Light… | installed（变量字体，一个文件三档都 `exact`） |
| `Inter` / `Source Serif 4` | — | **bundled**（随引擎，仅拉丁字形） |

```text
frame.create  {rect:[…], content:"text", text:"中文样本 永字八法 得意黑 ABC 0123"}
selection.set {ids:[<frame id>]}
type.char     {attrs:{fontFamily:"Smiley Sans", fontStyle:"Oblique", size:36}}
font.list     {}      # 只列「文档里用到的字族」，所以必须先把字体应用到文本；它没有 filter 参数
```

判读 `font.list`：`matchStatus:"exact"` + `source:"installed"` + `missing:false` 才算认出来；出现 `replacementFamily` 就是被替换了。

**两条必须一起查，缺一不可：**

1. `matchStatus:"exact"` **不代表中文能排** —— Inter 是 bundled + exact，汉字全是豆腐块。
2. **字体缺失时 DesignCraft 逐字回落，中文照样显示、只是字体不对** —— 光看图会把"没装好的字体"误判成"装好了"。

### 5.4 装完要做什么 / 已知限制

- **运行中的 DesignCraft 进程看不到新字体，但不用重启**：`font.reload {}` 即生效（实测 cataloged 380→382）。全新的 `designcraft-cli` 进程启动就能看到。
- **DesignCraft 直接扫字体目录，不读 HKCU 注册表**（实测删掉注册表值后仍 `exact`）；注册表是给 Word / PS 这类软件看的，但**仍然要写**。
- **覆盖已安装的字体文件会被拒**：`Copy-Item` 报 `user-mapped section open`。换版本先 `RemoveFontResourceW` + 删注册表值 + 删文件，再装。
- **同族同字重的 .otf 和 .ttf 不要同时装**（会撞车）。
- 字体是"机器级状态"：交付说明里必须点名装了什么、怎么卸（`Install-UserFont.ps1 -Uninstall`）。

---

## 6. 记账与署名（不做这一步等于白干）

`manifest.json` 每条记录的字段：`asset / file / role / source / provider / title / creator / license / licenseUrl / landingUrl / downloadUrl / width / height / bytes / sha256 / licenseRisk / fetchedAt`。

交付规矩：

1. 有 CC BY / CC BY-SA 素材 → **必须**署名，成品页脚或回复里给：`作者 + 许可证 + 来源链接`。
2. 只有 CC0/PD → 不强制，但把 `CREDITS.md` 一起交，客户/印厂会问。
3. `licenseRisk=true` → 交付说明里写清风险，别闷着。
4. 素材与版面的对应关系写一句（"封面主图为葛饰北斋《神奈川沖浪裏》，The Met Open Access，CC0"），比贴一堆链接有用。

---

## 7. 踩过的坑（都是实测）

| 坑 | 现象 | 处理 |
|---|---|---|
| 执行策略 | `& script.ps1` → 「在此系统上禁止运行脚本」 | 用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File …`；不改系统策略 |
| 脚本编码 | Windows PowerShell 5.1 按 ANSI 读 UTF-8 无 BOM 的 `.ps1` → 中文注释变乱码、解析报 `Unexpected token` | 脚本必须 **UTF-8 with BOM**；改完脚本重存一次 |
| **UA 是分水岭** | 无浏览器 UA → Openverse / Iconify 403 Cloudflare `Error 1010`；Wikimedia 用 bot UA → 403 `Please set a user-agent…` | 脚本统一发一个带联系方式的 UA；Wikimedia 再慢 0.5–1 s 一次 |
| Wikimedia 429 | `Too many requests`，带 IP | 同 UA 策略 + 间隔 + 不并发 |
| Wikimedia 缩略图档位 | 手写 `iiurlwidth=1600/2400` → 400 `Use thumbnail sizes listed on …`；而且 `thumbwidth` 与实际像素**不一致**（写 1600、实得 1920） | 只用 20/40/60/120/250/330/500/960/1280/1920/3840 这些档位；要原图用 `Special:FilePath?width=1920` |
| Wikimedia 直链 | `thumburl` 带 `?utm_source=commons.wikimedia.org…` | 下载前去掉查询串 |
| **Met 接口** | `/public/collection/v1/search` 已 410 退役；v1.1 结果里还会混进非 PD 条目 | 用 `/v1.1/search?…&offset=0&limit=50`，并**逐条**核 `objects/{id}.isPublicDomain` |
| **Openverse 限额** | `page_size=500` → 401 `may not exceed 20 for anonymous requests`；`page=999` → 401 翻页深度超限；突发约 20 次后读超时、无 `Retry-After`，冷却约 5 分钟 | 脚本把 `page_size` 夹到 20 以内、失败就提示换源；**别把 Openverse 当主源** |
| **元数据尺寸会骗人** | Openverse/stocksnap 条目自称 6016×4016，实得 960×641（`url` 是 `img-thumbs/960w`） | 恒按下载后的实测像素筛（脚本内建），别信 API 报的宽高 |
| 原图过大 | 博物馆原图 8000px+、变量字体 25 MB | 下载后按版面重采样（PhotoCraft `image.crop`），大字体只留需要的字重 |
| SVG | DesignCraft 置入报错/无图；PhotoCraft 只给 256px | 走 `Rasterize-Svg.ps1` |
| PS 5.1 JSON | `@(...) \| ConvertTo-Json` 会写成 `{value,Count}` 畸形结构 | 逐条序列化再拼数组（脚本里已处理，别退回旧写法） |
| PS 5.1 读文件 | `Get-Content` 默认按 ANSI 读，UTF-8 无 BOM 的中文文件会变乱码，**再写回就把文件写坏了** | 读写中文文本一律 `[System.IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)` |
| 字体装完看不到 | `font.list` 仍是 `missing` | `font.reload {}`（不必重启）；新建引擎进程启动即可见 |
| 字体家族名写错 | 写了 GDI 名 `"Manrope Light"` → `missing` → 回落 Source Sans 3 | 一律用 `font.list` 里的 typographic 名（`Manrope` + style `Light`） |
| 覆盖已装字体 | `Copy-Item` 报 `user-mapped section open` | 先 `RemoveFontResourceW` + 删注册表值 + 删文件，再装 |
| 许可传染 | 用了 CC BY-SA 素材，成品也背 same-license | 商业稿只用 CC0 / PD / CC BY |

---

## 8. 已验证 / 未验证（2026-10-30）

**已验证**
- 六个无 key 源 + 直链模式全部落盘成功，`manifest.json` / `CREDITS.md` 自动生成正确：
  Cleveland（2599×3400，CC0）、Met v1.1（3859×2594，CC0）、Wikimedia（1920×1291 / 3859×2594，PD 与 CC BY-SA 3.0）、
  Poly Haven（1024² / 2048²，CC0）、Openverse（5616×3744，CC BY-SA 3.0）、Iconify（ISC SVG）、google/fonts 直链（OFL TTF）。
- 许可门槛生效：小于 `-MinWidth` 的候选被跳过并写明原因（实测 Openverse 1024×768 < 1600 被拒）；图标集黑名单会拒绝 `wordpress` 这类 GPL 集。
- SVG → 1024² RGBA 透明 PNG 成功（Edge headless，colorType=6）。
- 字体链路全通：下载 → 用户级安装（免管理员）→ `font.list` `exact`+`installed` → DesignCraft 实排中文无豆腐块。
  实测装成 3 款：得意黑（CFF/OTF）、霞鹜文楷（TTF 25.9 MB）、Manrope（变量字体，Light/Regular/Bold 三档均 `exact`）。
- 反例也验了：Inter（bundled）`exact` 但汉字全豆腐块；字体缺失时逐字回落、中文仍"正常显示"——所以验证必须两头查。
- 端到端成稿：Met CC0《神奈川沖浪裏》→ PhotoCraft 裁切/调色/锐化 → DesignCraft 排版（得意黑标题 + 霞鹜文楷信息）
  → PNG 1191×1684 + PDF/X-4 `valid: true, warnings: []`（`designs/free-asset-demo/`）。

**未验证 / 不能保证**
- 需要 API key 的 Unsplash / Pexels / Pixabay / Smithsonian 只确认了"无 key 的正确拒绝"，没申请 key 实跑。
- 各源内容质量与接口字段都会变（Met 刚退役过 v1，Commons 的缩略图档位也改过）。
- CC BY-SA 的"衍生作品"边界是法律问题，本文件只给工程默认值（商业稿避开），不构成法律意见。
- 字体在具体印厂 / PDF-X 输出里是否嵌入正常，需按项目验证。
