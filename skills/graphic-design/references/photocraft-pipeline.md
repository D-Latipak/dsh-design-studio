# PhotoCraft 位图流水线（0.22.0 基线，0.17.0 实测配方）

平面设计里的照片/位图，全部在 PhotoCraft 里做完再交给 DesignCraft 排版。
本文件的命令 id、参数、返回结构在本机 `photocraft-cli 0.17.0` + MCP（headless）上跑通过；
2026-11-09 升级到 **0.22.0** 后命令只增不减（945 → 1000），核心链路未变。
0.22 新增：Classic Actions 面板命令（`actions.newSet` / `actions.recordAgain` / `actions.duplicate`…）、
`file.openAsSmartObject`、`layer.copyCSS`，CLI 新增 `--metadata none|all`。

## 0. 先搞清楚它的接口

PhotoCraft 的 MCP 不是「一个功能一个工具」，而是**一个命令引擎**：

| 工具 | 用途 |
|---|---|
| `command_list {}` | 查全部 **1000 条**命令（`{filter, enabled_only}`，`params` 字段是参数说明） |
| `command_run {id, params}` | 跑一条命令；长命令可 `wait:false` 走后台 job |
| `command_batch {steps:[{id, params}], stop_on_error}` | 顺序跑多条（**不回滚**，前几步失败前已生效） |
| `doc_open {path}` / `doc_new {width,height,mode,depth,background}` | 打开图片 / 新建画布 |
| `doc_inspect {}` | 图层树、history、选区、尺寸、色深、分辨率 |
| `render_preview {max_side}` | 当前画面预览 PNG（≤2048，默认 1024） |
| `doc_export {path, format, quality}` | 导出 jpg/png/tif/psd/…（**会合并图层**，有 warnings） |
| `doc_save {path}` | 存 `.pcraft`（无损原生）或 `.psd`（保留图层） |
| `doc_export_layers {dir}` | 每层导出成独立文件 |
| `session_list` / `doc_select` / `doc_close` | 多文档管理 |

**文件边界**：只认两个根目录（启动参数 `--automation-read-root` / `--automation-write-root`），
路径写相对根目录的路径或根内绝对路径。本 agent 的两个根 = 设计工作区
`C:\design-workspace`。被拒时的原文：
`automation path rejected: outside the read root …` / `outside the write root …`。

## 1. 标准五步（照片进版面之前）

```text
① doc_open      {"path": "designs/assets/mountain-dusk.png"}
② command_run   {"id": "image.crop", "params": {"x":168,"y":0,"width":2064,"height":1600,"targetWidth":2480,"targetHeight":1920}}
③ command_run   {"id": "image.adjustments.levels", "params": {"inBlack":10,"gamma":1.05,"inWhite":250}}
④ command_run   {"id": "filter.sharpen.smartSharpen", "params": {"amount":55,"radius":1.2,"reduceNoise":10}}
⑤ doc_export    {"path": "designs/<slug>/photo-graded.jpg", "format": "jpg", "quality": 92}
```

- ②的 `targetWidth`/`targetHeight` 必须**同时给**：裁切与重采样在同一步完成（等价 Image Size）。
- ③ 之后可以叠加 `image.adjustments.vibrance {"vibrance":22,"saturation":-6}`、
  `image.adjustments.curves {"points":[[0,0],[64,52],[192,208],[255,255]]}`、`image.adjustments.colorBalance` 等。
- ④ 放在重采样**之后**；印刷稿 amount 40–70、radius 1–1.5；屏幕稿 20–40。
- ⑤ 之后必须 `read_image` 看一眼再进版面。

## 2. 尺寸换算（印刷/屏幕）

| 目标 | 公式 | 例 |
|---|---|---|
| 印刷 300dpi | 像素 = pt × 4.1667 | 版面宽 595pt → 2480px |
| 印刷 300dpi（按 mm） | 像素 = mm × 11.81 | 210mm → 2480px |
| 屏幕 2× | 像素 = 版面 px × 2 | 1080 方图 → 2160px |

裁切比例 = 版面框宽高比。例：照片占 595pt × 460pt（1.29:1），原图 2400×1600（1.5:1）
→ 左右各裁 `(2400 − 1600×1.29)/2 ≈ 168px`，再重采样到 2480×1920。

## 3. 常用命令速查（实测参数）

| 需求 | 命令 id | 参数 |
|---|---|---|
| 裁切 + 重采样 | `image.crop` | `{x,y,width,height,targetWidth,targetHeight,resample}` |
| 仅改像素尺寸 | `image.imageSize` | `{width,height,resample:"lanczos"}`（或 `percent`/`resolution`） |
| 改画布/加边 | `image.canvasSize` | `{width,height,anchor,extensionColor}` |
| 影调 | `image.adjustments.levels` | `{inBlack,gamma,inWhite,outBlack,outWhite}`（0..255） |
| 曲线 | `image.adjustments.curves` | `{points:[[in,out],…]}`（2..19 点，0..255） |
| 明暗/对比 | `image.adjustments.brightnessContrast` | `{brightness:-150..150, contrast:-50..100}` |
| 氛围 | `image.adjustments.vibrance` | `{vibrance:-100..100, saturation:-100..100}` |
| 色相/饱和/明度 | `image.adjustments.hueSaturation` | `{hue,saturation,lightness}` |
| 锐化（推荐） | `filter.sharpen.smartSharpen` | `{amount:1..500, radius:0.1..64, reduceNoise:0..100}` |
| USM | `filter.sharpen.unsharpMask` | `{amount,radius,threshold}` |
| 模糊 | `filter.blur.gaussianBlur` | `{radius}` |
| 旋转/翻转 | `image.imageRotation.90cw` / `.flipCanvasHorizontal` 等 | `{}` |
| 自动影调 | `image.autoTone` / `autoContrast` / `autoColor` | `{}` |
| 去背景（选区） | `select.subject` / `select.object` | `{}`（之后再蒙版/删背景） |
| 智能对象 | `doc_place {path}` / `doc_replace_smart_object` | 外部素材作为智能对象置入 |
| 导出 | `doc_export` | `{path,format,quality}`（jpg 建议 90–95） |
| 存可编辑母版 | `doc_save` | `{path:"….psd"}` 或 `….pcraft` |

**撤销**：`command_run {"id":"edit.undo","params":{}}` 一次退一步；`doc_inspect` 的 `history` 数组可核对。
**做实验先复制**：`image.duplicate`（或 `history.newDocument`）生成副本再折腾，原图不动。

## 4. 交接到 DesignCraft（实测配方）

```text
# DesignCraft 侧：照片满版压底 + 文字压在上面
file.place   {"path":"designs/photo-demo/photo-graded.jpg","x":-8.5,"y":-8.5,"width":603.78}
frame.create {"rect":[-8.5,300,603.78,468],"content":"graphic"}
object.gradient {"kind":"linear",
                 "stops":[{"location":0,"swatch":"Ink","opacity":0},{"location":100,"swatch":"Ink","opacity":100}],
                 "from":[-8.5,300],"to":[-8.5,468],"target":"fill","ids":["<上方矩形的 id>"]}
```

- `file.place` 的 `width` 定宽、高度按图比例自动；也可以 `frame:<id>` 放进已有图框。
- 渐变**必须用 `from`/`to` 显式坐标**；`angle` 的方向容易反，反了会出现一条硬边。
- 渐变的 `stops` 支持 `swatch` 名 + `opacity`（0–100），印刷时跟随色板的 CMYK 值。
- 检查交接质量：`inspect_document` 里图片对象的 bounds 应裁得过版面（含出血），且 300dpi 达标。

## 5. 坑（都踩过）

1. **没给 roots = 没有文件权限**（`photocraft-cli mcp` 默认拒绝一切文件读写），不是 bug。
2. `doc_export` 导出 jpg/png **会合并图层**（返回 `warnings: ["… flattened …"]`）；要保留图层请 `doc_save` 成 `.psd` / `.pcraft`。
3. jpg 导出会带 `"transparency composited over white"` 警告 —— 需要透明就用 png。
4. `image.crop` 的 `resolution` 只是元数据（默认沿用原图 ppi，实测会显示 96），**真正决定印刷质量的是像素尺寸**。
5. 锐化放在重采样之后；先锐化再缩放等于白做。
6. `command_batch` 失败不回滚，前几步已生效；批量前先 `doc_inspect` 记下 history 长度，失败后按步数 `edit.undo`。
7. 大滤镜（降噪、内容识别填充、Photomerge）可能走后台 job：`command_run` 带 `wait:false` 时返回 `{"job": id}`，用 `jobs_list` 轮询。
8. 别在 PhotoCraft 里拼版面、打字排版 —— 那是 DesignCraft 的活，字体/出血/PDF/X 它才管得对。

## 6. 联动出口（位图 → 矢量 / 矢量 → 位图往返）

PhotoCraft 是素材关的**加工车间**，不是终点。图处理完只有两条出口：

```text
出口 A（位图 → 矢量）：doc_export 成品图 → VectorCraft file.place → 字/形/版式压在图上
出口 B（矢量 → 位图 → 回置 / 成品）：VectorCraft export PNG → PhotoCraft 加质感 → 回置或直接交付
```

跨引擎交接按画面需要来（配方编号 R1–R6 见
`material-pass.md` §七。本文件只写 PhotoCraft 这一侧的动作与验收：

| 出口 | PhotoCraft 侧动作 | 产物（`designs/<slug>/assets/`） | 验收 |
|---|---|---|---|
| R1 满版底 | `doc_open`→`image.crop`（含 targetWidth/Height）→`image.adjustments.levels`→`filter.sharpen.smartSharpen`→`doc_export {format:"jpg",quality:92}` | `bg-graded.jpg` | 像素宽 ≥ 置入宽 pt × 4.1667；`read_image` 无假字/水印 |
| R2 回置加质感 | `doc_open`（读 VectorCraft 导出的 PNG）→`filter.gallery.filmGrain`→`image.adjustments.curves`→`doc_export` | `<slug>-textured.jpg` | 文字边缘不糊（源 PNG `scale` ≥ 4.1667）；源 `.vcraft` 保留 |
| R3 抠图 | `select.subject`（或 `layer.removeBackground`）→`select.inverse`→`edit.clear`→`doc_export {format:"png"}` | `cutout.png`（RGBA） | `doc_inspect` 尺寸/色深正确；边缘无白边/锯齿 |
| R4 纹理平铺 | `image.adjustments.levels`→`edit.definePattern`→`layer.newFillLayer.pattern`→`doc_export` | `tile-graded.jpg` | 拼接无接缝；整幅一张，不在矢量里重复贴 |
| R5 印刷质感 | `doc_open`（矢量导出的 PNG）→`filter.gallery.grain`→`image.adjustments.curves`→`doc_export` | `<slug>-print.jpg` | 位图成品；印刷 PDF 仍回 VectorCraft `document.exportPdf` 出 |
| R6 半调/阈值 | `image.adjustments.threshold` / `image.adjustments.posterize` / `filter.gallery.halftonePattern`→`doc_export {format:"png"}` | `halftone.png` | 网点在 100% 视图不断线；回矢量叠加时 `doc_inspect` 网点数量合理 |

规矩：

1. **回置前先 `read_image`**：PhotoCraft 里的预览和置入后的实际大小经常不是一回事。
2. **导出的分辨率按「置入尺寸 × 4.1667」算**，不是按原图算；R2/R5 的矢量导出用 `export {scale:4.1667}` 起。
3. **保留可编辑母版**：滤镜/调色前 `doc_save` 成 `.pcraft` 或 `.psd`，`doc_export` 会合并图层。
4. **颜色模式对齐**：印刷稿在 PhotoCraft 侧就按目标色彩处理，矢量里别再二次转；CMYK 稿的 PDF/X 由 VectorCraft 出。
5. **不做第二次压缩**：R1→R2 这种往返里，中间图用 PNG 或 quality ≥ 92 的 JPG，别把 JPG 反复存。
6. **`filter.gallery.*` / `edit.definePattern` / `layer.newFillLayer.pattern` 未逐项实测**：先 `command_list {filter:"…"}`
   看 `params` 再跑，小样试一张。

> 完整链路示例见 `assets-generation.md` §三（生图 → 落盘 → 裁切调色锐化 → 置入 → PDF/X-4），
> 与本节是同一套出口，只是把「生成」换成了「矢量导出」或「素材站下载」。
