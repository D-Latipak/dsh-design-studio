# 程序化网格：把"形状"写进代码，别写进参数

> 适用：有机物（水果、食物、石头、织物），以及任何图元表达不了、又不值得用生图的立体件。
> 工具：`scripts/proc-mesh.py`（numpy + Pillow，无第三方依赖、无网络）
> 输出：自包含 `.glb`（几何 + albedo + normal + metallicRoughness 全嵌入）→ `layer.newModel` 一次导入。
> 配套读：`effectcraft-3d.md`（引擎侧事实与坑）。

---

## 一、为什么要有这一步

`layer.new3dPrimitive` 只有六个图元、材质只有标量，**没有任何贴图/凹凸通道**。
所以"橘皮"在参数里永远表达不出来 —— 球只能是球。

而几何在代码里是**生成式**的：一个噪声函数给 81 000 个顶点各一个位移，橘皮的凹点就真的在几何上，
法线也是真的。**同样一次调用，图元给你一个参数，代码给你一个表面。**

---

## 二、最小用法

```powershell
$py = "<skill>\scripts\proc-mesh.py"
$out = "designs\<slug>\3d\orange"

python $py --preset orange --detail 360x225 --tex 1024 --out $out
# → orange.glb  orange_albedo.png  orange_normal.png  orange_mr.png  orange_rough.png  orange.json
```

然后（EffectCraft）：

```powershell
@('layer.newModel', @{path='<绝对路径>\orange.glb'; name='orange'; position=@(600,600)})
```

**不要**再给 model layer 设 `baseColor`/`roughness` —— 引擎会拒绝，材质全在文件里。

### 先干跑，再出文件

```powershell
python $py --preset orange --out $out --dry-run
```

会打印顶点数、半径极差、`silhouette_is_perfect_circle`。
**这个布尔值是验收指标**：`true` 就说明你做的还是一个完美的球，回去调 `--amplitude` / `--dimples`。

---

## 三、参数

| 参数 | 默认 | 作用 | 调它的直觉 |
|---|---|---|---|
| `--preset` | `orange` | `orange` / `stone` / `fabric` / `custom` | 只决定基色与材质配比，几何参数仍可覆盖 |
| `--detail` | `192x128` | 经度 × 纬度分段 | 凹点要看清就给 `320x200` 以上；每翻一倍顶点数 ×4 |
| `--radius` | `1.0` | 世界单位半径 | 引擎里靠 `transform/scale` 缩放，别为尺寸重生成 |
| `--amplitude` | 按 preset | 高频起伏幅度（相对半径） | 橘皮 0.008–0.012；石头 0.04–0.07 |
| `--frequency` | 按 preset | 噪声频率 | 越大颗粒越细；>30 在 1024 贴图里会开始糊 |
| `--octaves` | 按 preset | 噪声层数 | 4 够用；6 更自然但更慢 |
| `--dimples` | 按 preset | 凹点密度（每边个数，0=关） | 橘子 24–32；石头 6–10；不需要就 0 |
| `--dimple-depth` | 按 preset | 凹点深度（相对半径） | 0.012–0.02 才在轮廓上看得出来 |
| `--tex` | `1024` | 贴图边长 | 印刷稿 2048；预览 1024 足够 |
| `--format` | `glb` | `glb` / `gltf` / `obj` / `both` | 给 EffectCraft 一律 `glb` |
| `--seed` | `7` | 随机种子 | 换一个数就是一个新个体，几何与贴图同步改变 |

---

## 四、调参循环（三步，不要多）

1. **看轮廓**：`--dry-run` 看 `radius_rel_spread` 与 `silhouette_is_perfect_circle`。小于 1% 就把 `--amplitude` 或 `--dimple-depth` 加倍。
2. **看表面**：渲一帧，**裁主体那一块**看（不要看 4K 全图）。表面还是均匀 → 贴图没进来，回 `effectcraft-3d.md` 第三节；
   表面像发霉 → `color_variance` 或 `rough_variance` 太大。
3. **看光**：轮廓对了但发灰 → 加了一盏不够亮的 Key，或 Ambient 太高（把 Ambient 压到 20–30）。

一次只改**一个**数字，并且能说出改了什么。改两处就分不清是谁的功劳。

---

## 五、坑

| 现象 | 原因 |
|---|---|
| EffectCraft 里表面是均匀塑料 | glTF 的 `metallicFactor: 0` 把 MR 贴图乘没了；或 `baseColorFactor` 不是 1，颜色被乘暗 |
| 表面被当成金属、发灰反光 | 塞进 metallicRoughness 的是灰度图（B 通道 = roughness → metallic）。本脚本会单独出 `_mr.png`，别替换它 |
| 轮廓像被压扁的球 | UV 球在极点有退化三角形；真实物体也不该完美对称——加 `--amplitude` 的低频项即可 |
| 接缝处一条竖线 | 等距柱状 UV 的固有接缝，放在背面或靠机位避开 |
| 生成很慢 | 凹点计算是 O(顶点 × 凹点数)。`--dimples` 减半即可；贴图不参与凹点计算（凹点已在几何里） |

---

## 六、什么时候**不要**用

- 规则几何体（盒子、瓶子、设备、等距结构）→ 直接用 `layer.new3dPrimitive`，别绕。
- 照片级人物、复杂场景、商品实拍感 → `generate_image` 更快更真。
- 客户已有模型 → 直接用客户的，不要重造。

判据：**这张画面需不需要正确的三维关系，且主体是不规则有机体？** 是 → 程序化网格；否 → 图元或生图。
