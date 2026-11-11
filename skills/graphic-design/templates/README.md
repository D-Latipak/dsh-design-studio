# 设计模板库（A：设计系统 + 参数化模板）

**为什么**：每次都让模型从零算坐标，质量方差大、调用次数多。这里把经过验证的版式固化成模板，
agent 只填「槽位」（标题/信息/照片/配色），再交给 DesignCraft 排版 —— 从「发明几何」变成「选择 + 填空」。

## 文件

| 文件 | 作用 |
|---|---|
| `design-tokens.json` | 设计 token：6 组色板（同时给 hex + CMYK）、字体、间距、字号阶梯、硬性规则（最小字号/安全边/最多色数） |
| `poster-a4-photo.json` | A4 印刷海报：照片顶栏（裁切填满）+ 深色文字区，槽位 kicker/title/en/deck/info/price/photo |
| `social-1080.json` | 1080×1080 社媒方图：照片满版 + 顶部压暗 + 底部渐变文字区 |
| `card-90x54.json` | 90×54mm 名片：深底 + 左侧姓名/职务/联系 + 右上色块 |
| `build.mjs` | 构建器：模板 + 槽位值 → `.dcs` 脚本 →（可选）直接排版导出 PNG/PDF |

## 用法

```bash
# 1) 看有哪些模板和槽位
node build.mjs --list

# 2) 准备槽位值（JSON 文件；含中文时务必用文件，不要命令行内联——PowerShell 会剥引号）
#    values.json: {"photo":"designs/assets/x.jpg","title":"墨山","palette":"wine",...}
node build.mjs --template poster-a4-photo --values values-poster.json --slug my-poster --out designs/my-poster --run

# 3) 只生成脚本（自己检查/改）
node build.mjs --template card-90x54 --values values-card.json --slug card --print

# 4) 换色板（6 选 1）与印刷/屏幕模式
node build.mjs --template social-1080 --values v.json --palette electric --mode rgb --slug s --run
```

`--run` 会输出：`<slug>.dcs`、`<slug>.designcraft`、`<slug>.png`；印刷模板额外出
`<slug>.pdf`（PDF/X-4，`bleed:true`）。构建完成后**必须**再跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\scripts\Test-Design.ps1 -Design designs/my-poster/my-poster.designcraft
```

## 色板（`design-tokens.json` → palettes）

`ink-night` 墨夜（深蓝+暖橙）· `warm-paper` 暖纸（浅底+砖红）· `moss` 苔绿 · `electric` 电光 ·
`wine` 酒红（高级/展览）· `slate` 石板（商务）。

印刷模板默认 `mode: cmyk`（走 CMYK 色板，PDF/X-4 不告警）；社媒模板 `mode: rgb`。

## 加新模板

复制一个模板 JSON，改 `id/name/when/format/slots/ops`。约定：

- 槽位用 `{{slot}}`；字体用 `{{font.serif}}` / `{{font.sans}}`（来自 tokens）。
- 步骤名 `as` 之后可被引用：`{{#title.id}}` → batch 的 `$N.id`。
- 步骤可加 `"when": "price"`：该槽位为空时整组跳过。
- 色板名固定 `Ink / Paper / Accent / Support`。
- 版式改动后用 `Test-Design.ps1` 和 `read_image` 双重验证再交付。
