# HTML 起手模板（templates/）

四份可直接改的稿子，都自带色板变量、安全边距与 audit 忽略标记。
复制到 `designs/<slug>/` 再改，不要在原文件上改。

| 文件 | 尺寸（CSS px） | 渲染命令 | 用途 |
|---|---|---|---|
| `poster-a4.html` | 794 × 1123 | `-Width 210 -Height 297 -Unit mm -Dpi 300 -Audit` | A4 海报 / 展览 / 活动（印刷走 DesignCraft 重排文字） |
| `social-1080.html` | 1080 × 1350 | `-Width 1080 -Height 1350 -Scale 2 -Audit` | 小红书 / 社媒 3:4；改高即可 1:1 / 9:16 |
| `long-page-1080.html` | 1080 × N | `-Width 1080 -FullPage -Audit` | 长图 / 多节图文；每节 720 高 |
| `ui-mock-1440.html` | 1440 × 900 | `-Width 1440 -Height 900 -Scale 2 -Audit` | 界面稿 / 看板 / 产品页示意 |

统一规则：

- 色板写在 `:root` 的 CSS 变量里；取值来自 `../graphic-design/templates/design-tokens.json`（hex 用于屏幕，CMYK 只用于 DesignCraft 印刷稿）。
- 装饰性满版元素加 `data-audit-ignore`，否则 audit 会判越界。
- 有照片就用 `<img>` + `object-fit:cover` + 一层 `scrim` 保证文字对比度。
- 字体用家族名；随包 OFL 字体在 `../graphic-design/assets/fonts/`，用相对路径 `@font-face` 引入。
- 渲染完必须 `read_image` 看一遍；audit `errors: 0` 只是及格线，风格与构成按用户要求来（本 bundle 不打风格分）。
