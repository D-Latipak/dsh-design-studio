# 产线 E · EffectCraft 3D（实测基线：effectcraft-cli 0.23.0）

> **一句话定位：EffectCraft 是虚拟摄影棚，不是建模器。**
> 它负责**打光、机位、透明出帧、合成**；**形状与材质必须从模型文件进来**。
>
> 这条以前写错成「用图元建真实几何」，结果是：一个 `radius=1500` 的球被当成橘子交稿。
> 那不是 token 不够，是**这套命令面里根本没有"橘皮"这个旋钮**。

---

## 一、命令面事实（别猜，这就是全部）

| 能力 | 真实取值 |
|---|---|
| `layer.new3dPrimitive` | `kind: cube \| sphere \| plane \| torus \| cone \| cylinder` —— **只有六种** |
| 图元材质 | `baseColor / metallic / roughness / emissive / lightTransmission` —— **全是标量** |
| 贴图通道 | **没有。** 没有 normal、没有 bump、没有 displacement、没有 UV 贴图 |
| 真几何入口 | `layer.newModel`：`path` 接受 `.gltf / .glb / .obj / .stl / .fbx` |
| 模型材质 | **完全来自文件**。`material.set` 对 model layer 拒绝 `baseColor/metallic/roughness`（"a model layer keeps its file's materials"）；`props` 只暴露 `castsShadows/acceptsShadows/acceptsLights/appearsInReflections` |
| MCP | 有，但**故意不挂**：749 条命令会把工具定义撑爆。只走 CLI |

**推论**：图元的形状上限就是"球/盒/柱"，表面上限就是"均匀基色 + 单一粗糙度"。
有机物（水果、食物、人、动物、植物、织物、石材、皮革）**永远不要指望图元**。

---

## 二、几何从哪来（按这条顺序选，不要跳）

| # | 来源 | 什么时候 | 怎么做 |
|---|---|---|---|
| 1 | **客户/用户给的模型** | 有 `.glb/.gltf/.obj/.stl/.fbx` | 直接 `layer.newModel`，不改造 |
| 2 | **程序化网格**（首选自制路径） | 有机物、需要可控变体、"要真的像" | `scripts/proc-mesh.py` → `.glb` |
| 3 | **AI 生图** | 需要照片级质感、人物、复杂场景 | `generate_image`，当位图素材用 |
| 4 | **图元** | 只用**规则几何体**：盒子、瓶子、设备、等距结构、抽象雕塑、立体字 | `layer.new3dPrimitive` |

**为什么程序化网格优于图元**：一个 token 在图元里只能改一个标量；在代码里能生成上千个顶点。
橘皮的凹点是一个噪声函数，不是一个参数 —— 这就是网页版 AI「几行代码一个橘子」的真实原因。
形状归代码，光影归引擎。

**红线**：写实/有机主体用图元顶替 = 交付失败；生图不可用时改用图元顶替 = 更严重的失败（该升级）。

---

## 三、`layer.newModel` 的材质保真度（2026-11-10 逐项实测）

五个测试全部通过（每项都有"去掉贴图的对照组"做像素差比对）：

| 测试 | 结论 | 证据 |
|---|---|---|
| T1 `.obj` + `.mtl` + PNG diffuse | **PASS**：贴图正确 UV 包裹 | 红/青棋盘出现在球面 |
| T2 `.gltf` + `.bin` + PNG albedo | **PASS** | 去掉 `baseColorTexture` 的同款材质 = 纯灰（像素差 207） |
| T3 `.gltf` + normal map | **PASS**：只剩明暗变化、轮廓仍是圆 | 对照组光滑（像素差 119） |
| T4 `.glb` | **PASS**：与等价 `.gltf` **像素完全相同**（差 0） | — |
| T5 metallicRoughness 贴图 | **PASS**：金属/粗糙度两个通道都有效 | 差 74 / 130；标量 factor 也生效 |

**结论：PBR 贴图能完整穿过 `layer.newModel`。** 所以"形"和"质"可以一起从文件进来。

### 推荐路径：单个自包含 `.glb`

贴图全部嵌进 GLB 的 BIN chunk → **一次 `layer.newModel`，不需要解析 `.bin` 或图片 URI**。
`proc-mesh.py` 默认就出这种文件。`.gltf` + 外链 `.bin` + 外链 PNG 也能用，但多三个路径解析点。

### 三个会静默毁掉画面的坑

1. **`metallicFactor: 0` 会把整张 metallicRoughness 贴图乘成 0** —— 粗糙度图直接失效，表面变成均匀塑料。
   有 MR 贴图时 factor 必须是 1。
2. **`baseColorFactor` 不是 1 时会把已烘好颜色的 albedo 再乘一遍** —— 整体发暗。
   有 albedo 贴图时 factor 给 `[1,1,1,1]`。
3. **glTF 的 metallicRoughness 贴图通道约定是 G=roughness、B=metallic。**
   直接塞一张灰度图，B 也等于 roughness，表面会被当成金属。必须单独出一张 RGB：`R=1, G=roughness, B=0`。
   `proc-mesh.py` 会同时出 `_rough.png`（给人看/给 OBJ）和 `_mr.png`（给 glTF）。

另：**金属材质需要 Environment 灯才读得出反射**（`layer.newLight {kind:'Environment'}`，或把 equirect 图层指给它）。非金属主体用 Ambient + Spot 就够。

---

## 四、五步出帧

### 1. 写命令文件（不要内联 JSON）

PowerShell 会吞掉 `--params '{"a":1}'` 里的双引号。**一律 `run --args-file`**，且参数文件必须是 **UTF-8 无 BOM**：

```powershell
$fx = "$env:LOCALAPPDATA\Programs\ArtCraft\EffectCraft\effectcraft-cli.exe"
$cmds = @(
  @('comp.new',            @{name='hero'; width=3000; height=3000; renderer='advanced3d'}),  # 不要 background！
  @('layer.newLight',      @{kind='Ambient'; name='amb'; intensity=26}),
  @('layer.newLight',      @{kind='Spot'; name='key'; intensity=230;
                             position=@(-620,780,-760); poi=@(600,600,0); coneAngle=125; coneFeather=90}),
  @('layer.newLight',      @{kind='Spot'; name='rim'; intensity=130;
                             position=@(1150,900,-300); poi=@(620,620,0); coneAngle=110; coneFeather=90}),
  @('layer.newCamera',     @{name='cam'; preset='50mm'; position=@(600,600,-1500); poi=@(600,600,0)}),
  @('layer.newModel',      @{path='<绝对路径>\orange.glb'; name='orange'; position=@(600,600)})
)
$lines = @(); foreach($c in $cmds){ $lines += $c[0]; $lines += ($c[1] | ConvertTo-Json -Compress -Depth 8) }
[System.IO.File]::WriteAllText($af, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
& $fx run --args-file $af --empty --save-as $proj --json
```

### 2. 模型尺寸与姿态

模型导入后按文件自身单位落位，层上有 `transform/scale`（默认 `[100,100,100]`）与 `transform/position`。
摆不下就用 `set` 改，**不要重新导出模型**：

```powershell
& $fx set hero orange "transform/scale"    "[160,160,160]" --project $proj --save
& $fx set hero orange "transform/position" "[600,600,0]"   --project $proj --save
& $fx props hero orange --flat --project $proj   # 看真实属性路径
```

### 3. 出帧

```powershell
& $fx render-frame --project $proj --comp hero --frame 0 --transparent --out "$d\hero.png"
```

### 4. 先看，再交

`read_image` 看 —— **但看裁切到主体边界的局部，不要看整张 4K**（见章程 §4）。
检查项：轮廓是否仍是几何体的规则感、贴图有没有生效（表面是否只有均匀基色）、投影方向、主体会不会被裁。

### 5. 进版面

`hero.png → PhotoCraft 调色/加颗粒 → VectorCraft / DesignCraft file.place`。
要「立体又可编辑」：`imageTrace.makeAndExpand` 转路径。

---

## 五、图元清单（只有这些，照抄）

```powershell
@('layer.new3dPrimitive', @{kind='cube'; name='box'; width=380; height=380; depth=380;
   position=@(700,470,0); baseColor='#d9c3a3'; metallic=0.3; roughness=0.28;
   castsShadows=$true; acceptsShadows=$true})
```

图元没有 rotation 参数，建完用 `set ... "transform/orientation" "[x,y,z]"`。
`plane` 默认直立，要当地面得转 `[90,0,0]`。

`kind` 首字母必须大写：`Spot` / `Point` / `Parallel` / `Ambient` / `Environment`。

---

## 六、实测坑清单

| # | 现象 | 原因与解法 |
|---|---|---|
| 1 | `--transparent` 出了不透明图 | **comp 设了 `background`**。要透明就别传 |
| 2 | `--max-side 4961` 出图还是 1400 宽 | `--max-side` **只降不升**；要 300dpi 就把 comp 建那么大 |
| 3 | `params are not valid JSON` | PowerShell 吞引号 → 用 `run --args-file` |
| 4 | `unknown command '﻿comp.new'` | args-file 带 BOM → `UTF8Encoding($false)` |
| 5 | 相机正对主体，渲出来是平的 | `poi` 与 `position` 在同一条光轴上 → 给偏轴 30–45° |
| 6 | 地面成了一面墙 | `plane` 默认直立 → `transform/orientation [90,0,0]` |
| 7 | 物体全黑 | 灯光 `kind` 首字母没大写 |
| 8 | 表面是均匀塑料 | 贴图没进来（见第三节三个坑），或材质根本没随文件导入 |
| 9 | 大场景渲染慢 | 加 `--gpu`；先 `--quality draft` 试构图 |

实测渲染时间：3000×3000 透明帧 ~1–2 s；81 000 顶点的程序化网格 + 1024² 贴图，**生成 5 s、渲染 1 s**。

---

## 七、打印尺寸（300 dpi，直接建这么大的 comp）

| 成品 | 毫米 | 像素 |
|---|---|---|
| A4 | 210 × 297 | 2480 × 3508 |
| A4 + 3mm 出血 | 216 × 303 | 2551 × 3579 |
| A3 | 297 × 420 | 3508 × 4961 |
| A2 | 420 × 594 | 4961 × 7016 |
| 社媒方图 | — | 1080 × 1080 |

3D 渲染成本跟**场景复杂度**走，不跟分辨率走 —— 一开始就把 comp 建到最终尺寸。

---

## 八、交付规矩

- 源文件：`designs/<slug>/3d/<slug>.ecproj`（客户能改机位/灯光）+ 模型文件（`<slug>.glb`）+ `proc-mesh.py` 的参数快照 `.json`
- 中间件：`<slug>-hero.png`（透明）、`<slug>-hero-graded.jpg`
- **不要把 hero.png 当成品交付**：字不可编辑、无 CMYK。成品必须落在 `.vcraft` / `.designcraft`
- 交付说明写：「主视觉由 3D 渲制（EffectCraft），几何为程序化生成 / 客户模型，源工程与生成参数随附，可改机位与形状参数」

---

## 九、效果与效率的真实对比

| 维度 | 手绘矢量（A） | 生图（generate_image） | 3D 静帧（E） |
|---|---|---|---|
| 首稿速度 | 快、确定性高 | 最快 | 中：要建/生成模型 + 打光对机位 |
| 透视/投影正确性 | 靠手感，易错 | 靠模型，常错 | **保证正确** |
| 多角度/多版本 | 每个重画 | 重新生成，主体会漂 | **改数字** |
| 分辨率 | 无限 | 受模型限制 | 大 comp 直接出 |
| 可编辑性/印刷 | **最好** | 差（位图） | 差（位图） |
| 模板化风险 | 中 | 高 | **图元高 / 程序化网格低** |

结论：**E 有两条入口判据，满足任一条就上 E：**
① 这张画面需要正确的三维关系（体积、透视、遮挡、投影、多角度一致）；
② 这张画面需要一个**图案 / 插画 / 装饰母题**——**建模再平面化是本工坊的默认画法**（见 `3d-to-graphic.md`），
   比手绘矢量更可控、更好改。

反过来：**照片级质感**（人物、皮肤、真实场景）而三维关系不重要 → 生图；纯几何与文字 → 直接矢量画。
