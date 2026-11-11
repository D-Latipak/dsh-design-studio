# 素材生成：3D 建模 + AI 生图 + SVG 代码（实测）

> **图案的第一来源是 3D，不是矢量笔。** 需要图案 / 插画 / 图标型母题 / 装饰元素时，
> 先建模再平面化：`references/3d-to-graphic.md`（建几何 → 压平光 → 透明出帧 → 位图或 `imageTrace` 转矢量）。
> 本文件只讲"必须自己造"时的**其余三条路**：AI 生图、程序化 SVG、手写简单几何。

> **画面来源见 `material-pass.md`。** 本文件是「怎么造」；「要不要造、造几张、怎么记账、怎么和矢量交接」在那边。
> 需要素材的活儿可以在等参考过审时并行开工（省时间），但**不是必做**：用户要纯文字/纯矢量/纯排版，就一张位图都不必造。

**画面优先用现成素材或生图，SVG 只做「必须自己控制」的那部分。** 顺序：

```
需求
├─ 照片 / 公共领域画作 / 纹理 / 图标集
│    → 先查 free-assets.md 的素材站（Cleveland/Met/Commons/Poly Haven/Iconify）
│       → 有合适的直接用 → PhotoCraft 修整 → 置入版面
├─ 插画 / 氛围图 / 概念主视觉（素材站没有、或需要特定构图）
│    → generate_image → 落盘 → PhotoCraft 裁切/调色/锐化 → 置入
├─ 矢量图形（艺术字 / 字形 / 印章 / 图标 / 纹样 / 图表 / 几何主视觉）
│    → 你写 SVG 代码 或 VectorCraft 画 → designs/assets/*.svg
│       → file.place（按导出分辨率栅格化，清晰度足够）
└─ 兜底
     → 以上都不可行才做占位版，交付说明写明
```

**不要用 SVG「画照片 / 画复杂插画」**：那是素材或生图的活，硬写成坐标只会得到程序感；
SVG 的强项是精确可控的图形、字形、图标、几何框架。

## 〇、矢量怎么来（重要：不要"凭描述手绘"）

**事实：模型对空间和曲线的控制很弱。** 让它用 `draw_shape` / `path.create` 一个点一个点地画插画、
产品、人物、机械、复杂图标，结果一定歪、抖、比例失真。这不是努力问题，是方法错误。

要矢量图形时，按这个优先级**生成**，而不是**手搓**：

| 顺序 | 方法 | 工具 | 适合 |
|---|---|---|---|
| 1 | **3D 渲染 → 转矢量** | EffectCraft 建几何/灯/相机 → `render-frame --transparent` → VectorCraft `imageTrace.makeAndExpand` | 产品与包装、等距场景、立体字、几何装置、抽象雕塑、图标母版；透视光影是算出来的，不会抖 |
| 2 | **程序化生成** | 写 `.py`/`.js` 算坐标，输出 SVG 或 VectorCraft 步骤 JSON | 网格/纹样、数据图、图表、光栅半调、等距网格、排线、路径变形、公式驱动的字形 |
| 3 | **引擎生成类命令** | `object.vectorHalftone`、`imageTrace.*`、`path.effect.*`、`pattern.*`、`text.createOutlines` + 变形 | 位图→矢量、半调、描边、变形、图案填充 |
| 4 | **手写简单图元** | `draw_shape`（矩形/圆/线/多边形/星）、`add_text` | 版式框架、色块、分隔线、简单箭头；**超过 ~10 个锚点的自由曲线就回到 1–3** |

**做法要点：**

- 程序化 SVG 也遵守下面 §一 的实测规则（明确 `width/height`、只用基本图元、不依赖外部字体）；
- 用脚本生成时，把生成脚本和产物一起存进 `designs/<slug>/assets/`（可复现比一次性坐标值更有用）；
- 3D 路线先读 `references/effectcraft-3d.md`（comp 不设背景、`run --args-file`、透明出帧）；
  `imageTrace` 的参数先 `command_list {filter:"trace"}` 查，小样试一张再上正式稿；
- 生成完必须渲染看一眼，再置入版面。

## 一、写 SVG（矢量素材）

输出到 `designs/assets/<name>.svg`，用 `write` 工具直接写文件即可。**实测规则**：

1. **根元素**：`<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H" viewBox="0 0 W H">`，
   W/H 用像素整数（900、1080 等），画布比例如 1:1、3:4、16:9 都行。
2. **只用基本图元**：`rect/circle/ellipse/line/path/polygon/polyline/g` + `fill/stroke/stroke-width/
   stroke-dasharray/stroke-linecap/opacity/transform`。实测这些都正常。
3. **不要依赖**：外部字体文件、`<image>` 外链、`<filter>`/`<mask>`/`<clipPath>` 的复杂用法、
   CSS `<style>` 块。字距（`letter-spacing`）在导入后不保证生效——重要字距放到 DesignCraft 文字层去做。
4. **文字**：`<text font-family="Noto Serif SC, serif" font-size="54" fill="#1d2f45">中文</text>`，
   实测 CJK 正常渲染；`text-anchor="middle"` 可用。
5. **颜色**：hex 即可；深色底上要浅色元素，自己加背景 `<rect>`（SVG 默认透明）。
6. **必须给明确的 `width`/`height`**（不要 `1em`、不要只有 viewBox）：两个导入器都按它决定栅格化尺寸。
7. **命名空间 id 唯一**；文件 < 1 MB；SVG 里不要写注释掉的大块调试内容。
8. 写好先自检：文件能被 `read` 打开、根元素闭合；**然后必须在 DesignCraft/PhotoCraft 里真渲染一次看结果**。

置入（DesignCraft）：
```text
file.place {"path":"designs/assets/seal-mark.svg","x":790,"y":56,"width":270}
```
→ 返回 `{asset, id}`。**实测：DesignCraft 接受 SVG，但它内部仍转成位图资源（kind:"<image>"），按导出分辨率栅格化**
（同一 SVG 在 4× 渲染下比 2048px PNG 置入更锐），所以放大不糊的前提是「每次导出都按目标分辨率渲染」，而不是矢量可无限放大。

小图标/`1em` 尺寸的 SVG（Iconify 常见）必须先光栅化，否则会按 24px 级尺寸导入：
```text
# 先用技能脚本光栅化到目标像素（Edge 无头，透明 PNG）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skills>\graphic-design\scripts\Rasterize-Svg.ps1" -Path "designs\assets\icon.svg" -Size 2048 -Out "designs\assets\png"
```

PhotoCraft 打开 SVG：按 SVG 的**内在** `width/height` 栅格化（实测 900×900 的 SVG → 900×900 PNG），
所以它适合「把整张 SVG 图转成位图再调色/加滤镜」，不适合小图标放大：
```text
photocraft-cli run designs/assets/x.svg --out designs/assets/x.png
```

## 二、AI 生图（模型渲染）

工具（DSH 生图插件提供）：
- `generate_image {prompt, size, quality, count, model}` —— 文生图。`size` 用比例（1:1 / 16:9 / 9:16 / 4:3 …），`quality` auto/1k/2k/4k，`count` 1–4。
- `edit_image {prompt, source_image, …}` —— 图生图/改风格。**走 shim 已可用**（加元素/换局部靠谱，整幅换色不可靠）；
  用法与边界见下方「硬约束」第 4 条。
- 默认模型 = 「设置 → 生图配置」里默认渠道的模型。**当前本机是本地部署：渠道「本地 Z-Image (sd.cpp)」`http://127.0.0.1:11436/v1`（shim 转接层），模型 `z-image-turbo`**（8 步蒸馏、cfg 1.0、离线、无水印）；`11435` 是它背后的 sd-server 上游，插件不直连。
  只能使用已配置渠道目录中的模型；不要编造模型名。换渠道后先实测一张再干活。

**提示词要素**（一次写清，少来回）：主体 + 构图（视角/占比）+ 风格（水墨/扁平/胶片…）+ 色彩（给出 hex 倾向）+ 留白位置 + 光线 + **「无文字」**（模型写不好文字，文字交给排版层）+ 比例。
本地蒸馏模型对**短而具体的提示词**更稳（20–60 字），不要写成故事。

### 背景 / 底纹出图配方（素材关主力）

背景**单独出图**，不要从主视觉里裁一块放大——构图和留白都对不上。可执行口径：

```text
generate_image {
  prompt: "abstract washi paper, one soft chartreuse-to-vermilion gradient,
           risograph grain, empty upper third, no typography, no letters",
  size: "3:4",        // 按版面比例出：海报 3:4 / 社媒 1:1 / 横幅 16:9
  count: 2,           // 一次 2–4 变体，拼一张小 contact sheet 一起看
  model: "z-image-turbo"
}
```

1. **只写材质 / 色场 / 光线 / 留空**，20–60 词；**不写**「海报 / 标题 / 字体 / 日式」——会自己长假字。
2. **构图留空**写进提示词（`empty upper third`、`negative space on the left`），文字层才压得住。
3. **按目标比例出图**，不要方图硬裁成瘦长条；本地短边 1024，满版 A4 会不够（见硬约束第 2 条）。
4. 出图后 `read_image` 查假字/水印；变体用 `New-ContactSheet.ps1` 拼一张，别一张就定。
5. 定稿前做**对比测试**：把主标题色值/字重压上去看可读性（正文 ≥4.5:1、大字 ≥3:1）；不够就
   PhotoCraft `image.adjustments.levels` 压暗，或换变体。
6. PhotoCraft 走标准五步（裁切重采样 → levels → smartSharpen → `doc_export`）后再置入；平铺底纹见
   `photocraft-pipeline.md` 与 `material-pass.md` §五。

**实测坑：提示词里出现「海报 / 日式 / 标题 / 字体」这类词，Z-Image 会自己「发明」乱码汉字/假名**
（示例 `designs/assets/jp-web-test/_bad-example-fake-cjk.jpg`：画面自己长出像「東京」「備忘」的假字）。
所以：底图提示词只写**材质 / 色场 / 光线 / 留白**（例：`abstract washi paper with one soft chartreuse-to-vermilion gradient, risograph grain, empty, no typography`），
出图后先 `read_image` 查假字——有假字就换更抽象的提示词或裁掉，**绝不能把带假字的图当成品**。字一律留给矢量排版层。

**拿到图 → 落盘**（实测，关键一步）：
返回形如 `{"images":[{"attachment_id":"sha256:<hex>","media_type":"image/jpeg","bytes":117299,"width":1024,"height":1024,"name":"…-1.png"}]}`。
**注意 `name` 不可信**（本地渠道返回 `…-1.png`，实际字节是 JPEG）；扩展名按 `media_type` 定。附件对象在 DSH 附件库，路径可由 hex 推出：
```powershell
$hex = "<attachment_id 去掉 sha256: 前缀>"
$src = "$env:USERPROFILE\.dsh\attachments\v1\objects\" + $hex.Substring(0,2) + "\" + $hex
Copy-Item $src "designs\<slug>\assets\ai-<slug>.jpg"   # 扩展名按 media_type：image/jpeg → .jpg（素材本体放本项目 assets/，见 material-pass.md §四）
```
复制后用 `read_image` 确认（扩展名与实际格式不符会被拒），再进 PhotoCraft。

**硬约束（必须如实告诉用户）**：
1. **水印按渠道不同**：本地 Z-Image **无水印**；智谱 `glm-image` 的图右下角带「AI生成」水印且该渠道关不掉；
   火山方舟 / BytePlus 上游可在渠道设置里关掉 `watermark`。正式交付时按当前渠道处理，并**在交付说明里写明这是 AI 生成素材**。
   不要把「抹掉 AI 标识」当成常规操作。
2. **分辨率**：本地渠道短边 1024（实测 1:1 → 1024×1024，16:9 → 1792×1024），只够屏幕稿或小尺寸印刷位；
   A4 满版（2480px）需放大（会软）——印刷大图优先 SVG/矢量 + 真实照片，或把 AI 图当小面积插图。
3. **速度**：本地 RTX 4060 Laptop + Q5_0 量化，单张约 20–40s（实测直连 API 37.1s/1024²）。批量出图要算时间。
4. **图生图已经可用（走转接层）**：用户在本机做了转接层 `F:\AI\sd-cpp\tools\img_shim.py`，
   拓扑是 **插件 → `:11436`（shim，默认渠道地址）→ `:11435`（真的 sd-server）**：
   shim 把插件发来的 `/v1/images/edits`（multipart：`image` + `prompt` + `size`）翻译成 sd-server 原生
   `/sdcpp/v1/img_gen`（`init_image` + `strength`），轮询 job 后回 b64 —— 所以**直接调 `edit_image` 即可，不会再崩**
   （走 `ref_images` 的那条老路径才是会 `GGML_ASSERT` 崩溃的原因）。
   **2026-11-06 实测**：连续 3 次编辑 + 1 次文生图全部成功、服务未崩。
   - ✅ 擅长：**加元素 / 换局部内容**（实测「右下角加一枚朱红印章」成功，构图与留白保持完好）
   - ⚠️ 不擅长：**整幅换色调**（strength 固定 0.6，底图颜色强时改不动——试过把蓝色山峦改黄昏暖色，只出少量暖斑）
   - 用法：`edit_image {prompt, source_image: <上一次生成返回的整个 image 对象>, size}`
     提示词写清「保持构图/留白/配色不变，添加/替换 X」；改得太少就换更强的具体描述。
   - 想要更强改造：让用户在 `launch.ps1` 里调 `IMG_SHIM_STRENGTH`（0.75–0.85 大改），
     **调色一律优先 PhotoCraft**（levels/curves/colorBalance 比 AI 换色可靠得多）。
   - 尺寸：shim 限制总像素 ≤ 1536×1024 并对齐 16 的倍数（16:9 会等比缩到上限内）。

   ```powershell
   # 回退方案（不走 HTTP、不想动 shim 时）：sd-cli 独立进程跑 init_image
   & "F:\AI\sd-cpp\bin\sd-cli.exe" `
     --diffusion-model "F:\AI\sd-cpp\models\diffusion_models\z_image_turbo-Q5_0.gguf" `
     --llm "F:\AI\sd-cpp\models\text_encoders\Qwen3-4B-Instruct-2507-Q4_K_M.gguf" `
     --vae "F:\AI\sd-cpp\models\vae\ae.safetensors" `
     --offload-to-cpu --vae-tiling `
     --init-img "designs\assets\in.jpg" --strength 0.55 `
     -p "same ink painting, add a red seal stamp in the bottom right corner" `
     -W 1024 -H 1024 --steps 8 --cfg-scale 1.0 --sampling-method euler `
     -o "designs\assets\out.png"
   ```
   注意 `sd-cli` 会和 sd-server 抢显存：**同一时间只允许一个 sd 进程**，跑 sd-cli 前先停 server。
5. **启动/重启拓扑**：`:11436` = shim（`img_shim.py`，插件连它），`:11435` = sd-server（真正出图）。
   - 停掉 11435 的 sd-server → 所有生图变 502（`healthz` 会报上游不可用）；shim 挂了则 11436 连不上。
   - `start-server.ps1` 起 sd-server，`launch.ps1` 起整套（含 shim）。日志 `F:\AI\sd-cpp\tmp\server.{out,err}.log`。
   - 加载期约 20–30s，其间请求会 `ECONNRESET`；就绪后再等 5–10s 或先来一张小图预热。
   - 从 DSH 的 `pwsh` 里 `Start-Process` 启动会被绑在后台 job 的进程树上、job 结束即被杀；
     脱离启动用 WMI：`Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='…'}`。
   - **agent 默认不要自行重启用户的服务**：报错并给命令；只有用户明确要求时才代为拉起。
6. **版权/合规**：AI 素材可用于设计，但不得用于伪造证件、假冒他人作品、侵害商标/肖像；参考图会发送到所配置的 API 服务，涉密图不要上传。
7. **可复现**：交付时把用到的提示词、渠道、模型名、生成日期记进交付说明（或 `designs/<slug>/sources.md`）。

## 三、完整素材链示例（2026-11-06 本地渠道实测跑通）

```
generate_image（本地 Z-Image，size 16:9）
  → 1792×1024 JPEG，无水印，附件 sha256:dae1ce15…
落盘：designs/assets/ai-local-wide.jpg
PhotoCraft: doc_open → image.crop（裁到 1.417 版面比例 + 重采样 2480×1750）→ levels/vibrance → smartSharpen → doc_export
DesignCraft: file.new A4 → file.place 照片满版 → 顶部压暗 scrim（压住白色天空，让页眉字可读）
             → 底部渐变过渡到主色 → 标题/信息层 → file.exportPdf {standard:"x4"} → export_png
```

对应文件：`scripts/pc-local-wide.json`（PhotoCraft 步骤）、`scripts/poster-local-wide.dcs`（DesignCraft 排版）、
`designs/local-demo/`（成品：moshan-wide.designcraft / .png / .pdf，PDF/X-4 `valid: true` + PdfCraft `check {"ok":1}`）。

**排版要点（本地图偏浅时必须做）**：Z-Image 的水墨风经常是浅底；把文字压在浅底上会看不清。
正确做法是给文字区加**压暗 scrim**（同色系渐变，从 60–70% 不透明度过渡到 0），而不是改文字颜色硬凑。

**图生图改稿示例（2026-11-06 实测）**：把上一张成品作为 init image，用 `edit_image` 让模型加元素：

```
edit_image {prompt: "保持整体画面与配色不变，在画面右下角的留白处添加一枚小小的朱红色方形印章", size:"1:1",
            source_image: <上一次 generate_image 返回的 image 对象>}
→ 完成：右下角出现朱红小印章，山形/留白未变（结果：designs/assets/ai-local-img2img-seal.jpg）
```

反例：同一张图让它「整幅改成黄昏暖色」只出了少量暖斑——**换色调请回 PhotoCraft**。

## 四、坑

1. AI 返回的是**附件引用**，不是文件路径；不落盘就没法交给 PhotoCraft/DesignCraft。
2. `name` 字段的扩展名不可信（本地渠道给 `.png`、实际 JPEG），**按 `media_type` 定扩展名**，否则 `read_image`/PhotoCraft 会拒。
   直接 POST `/v1/images/generations` 拿到的是 PNG（`b64_json`），经插件转一手后变 JPEG。
3. `generate_image` 默认同步等待完成；要并行做别的事再用 `wait_for_completion:false` + `get_image_generation_task`，不要反复轮询。
4. **图生图现在是安全的**（走 shim 的 init_image 路径）：可以放心 `edit_image`。但它固定 strength 0.6，
   **加元素/换局部内容靠谱，整幅换色调不可靠**——换色/调色优先 PhotoCraft。别再走裸 `sd-server` 的 `/v1/images/edits` 直连。
5. **同一时间只允许一个 sd 进程**：`sd-cli` 和 `sd-server` 各占约 6.8GB 模型内存，并发会把服务挤崩
   （事件日志里没有 assert，进程直接消失）。要跑 `sd-cli` 先停 server，跑完再起。
6. 本地服务不是常驻守护进程：11435 是 sd-server、11436 是 shim；加载期请求会 `ECONNRESET`；
   崩了/没起就让用户跑 `launch.ps1`（或 `start-server.ps1`），从 DSH 里启动要用 WMI 脱离方式（见上）。
7. SVG 里写 `letter-spacing`：同一 SVG 在不同置入宽度下字距可能被挤压/重叠（实测 360pt 时出现，400pt 时正常）；
   重要字距放到 DesignCraft 的文字层设置，别依赖 SVG 属性。
8. SVG 光栅化后是位图，**不能再当矢量放大**；需要什么尺寸就按目标尺寸光栅化。
9. AI 图不要直接当「产品图/证据图」用——它是插画素材，不是实拍记录。
