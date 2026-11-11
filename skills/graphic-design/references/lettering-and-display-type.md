# 艺术字体 / 字形设计（Lettering & Display Type）

做「艺术字体」不是换一个花字体。它是**在字架上做设计决策**：拉长、切角、错位、变形、填图、绕路径——
每一次变形都要能回答「为什么是这一下」。这份文件管四件事：什么时候用哪种手法、命令怎么下、
哪里会静默失败、以及版权与审美底线。

配套：版式在 `layout-and-type.md`；风格参数按 `style-research.md` 从用户原话现场联网研究得出，
不套任何内置风格条目。

---

## 一、先分清四种「艺术字」

| 类型 | 做法 | 适用 | 代价 |
|---|---|---|---|
| **展示字体**（display type） | 直接用已设计好的标题字体（优设标题黑、庞门正道、得意黑…） | 90% 的商业需求：海报、活动、社媒 | 0；但容易撞脸，需要靠版式与配色做出差异 |
| **字体改造**（modified type） | 转曲后改锚点、拉伸、切角、加装饰 | logo、主标题、限量印刷、品牌字 | 中；文字不再可编辑，要留原始字 |
| **路径字形**（custom lettering） | `path.create` 从零画字母/笔画 | 一个词、一个标志、数字、印章 | 高；中文整字不建议手画 |
| **效果字**（treated type） | 封套变形、路径文字、图像填充、渐变、描边、混合 | 主视觉、封面、展览标题 | 低–中；最容易过度 |

**判断顺序**：现有字体够不够 → 不够就改造一个字 → 还不够才画路径 → 什么时候上效果由你决定。
没有「不许叠」这条规矩，只有「说不清就不加」。

---

## 二、七种手法（按上手成本排序）

> 标记「实测」的配方在本机 VectorCraft 0.18 上跑通过（2026-11-06），示例见
> `designs/lettering-lab/`。标「未实测」的只验证了命令存在，参数需先 `commands` / `command_list` 同款核对。

### 1. 逐字排布与错位（实测）

把每个字做成独立 `text.create`，分别给 `rotation`、位置、颜色、字号。
中文标题要「活」，通常不是换字体，而是**每个字 1–3° 的旋转 + 基线 ±4–10pt 的错位**。

```json
{"command":"text.create","params":{"x":190,"y":1000,"text":"山","size":640,
  "font":"Alibaba PuHuiTi","style":"Heavy","color":"#141414","rotation":-3}}
```

要点：
- `rotation` 绕 `x,y`（基线点）转，不是绕字框中心；大字号转 3° 就会明显位移，转完用 `object.move` 回位。
- 逐字做时先定一条**共同基线**，只让 1–2 个字离开它；全都在跳就是噪音。
- 需要统一缩放/随机抖动时用 `object.transformEach`（`scaleH/scaleV/rotate/moveH/moveV/random/seed`，实测：
  同一 `seed` 可复现；默认不改填充，看不出效果时先检查是不是和底色同色）。

### 2. 转曲 + 节点改造（实测，最像「设计字体」）

```json
{"command":"select.set","params":{"ids":[4]}},
{"command":"type.createOutlines","params":{}},
{"command":"document.inspect","params":{"depth":4}}
```

`type.createOutlines` 把选中的文字换成 **Group → Compound Path → 若干 Path**，返回 `{ids}` 是组 id。
内部结构（实测固定顺序）：Compound Path 一个，子 Path 依次是**外轮廓、内孔**，最后才是 Group。
记住这四层的 id，后面才能改：

```json
{"command":"path.moveAnchor","params":{"id":13,"subpath":0,"anchor":0,"x":140,"y":520}}
```

- `anchor` 是从 0 开始的锚点序号，**不知道序号就先 `document.inspect` 看 `anchors` 数量**，
  再用 `path.moveAnchor` 试 0/1/2，渲染一次看结果（不会报错，只会「没变化」）。
- 想整段换几何：`path.setAnchors {id, subpaths:[{anchors:[{x,y,in?,out?}],closed}]}`（未实测）。
- 想「拖一下」而不是精确改点：`path.reshape {id,x,y,dx,dy,tol,radius}`——在 (x,y) 附近抓路径拖 (dx,dy)，
  周边锚点按半径平滑跟随（实测会变形，返回值是 null，必须渲染确认）。
- 改完记得 `object.expand` 或直接导出；源文件保留原字（放隐藏图层或另存 `-type` 副本）。

**适合改什么**：字脚、横竖末端、钩、撇捺的收笔、连接处切口。
**不要改什么**：中文的识别骨架（比如「口」的四角全切圆），改完就不是那个字了。

### 3. 轮廓字 / 描边字（实测）

```json
{"command":"paint.setFill","params":{"ids":[6],"none":true}},
{"command":"paint.setStroke","params":{"ids":[6],"color":"#D7261E"}},
{"command":"stroke.set","params":{"ids":[6],"weight":2.5,"align":"center"}}
```

- `align: inside|outside` 对文字按字形轮廓算，做「空心字 + 外描边」很稳。
- 想要「字内还有一层线」：复制一份 → `object.scale` 缩到 92% → 只留描边 → 叠回去。
- 想要「把描边变成实心轮廓」：`object.path.offsetPath` 或 `object.expand {stroke:true}`（未实测）。

### 4. 路径文字（实测）

```json
{"command":"path.create","params":{"anchors":[{"x":64,"y":1012,"out":[210,948]},{"x":470,"y":976,"in":[310,916]}],"closed":false}},
{"command":"text.createInPath","params":{"path":8,"mode":"onPath","text":"TYPE GROWS IN THE GAP",
  "size":22,"font":"Inter","style":"Medium","color":"#141414"}}
```

- 路径的**绘制方向**决定字的正反；反了就用 `type.pathOptions {flip:true}`。
- 路径文字排不下会返回 `overflow`，必须处理（缩字号 / 加长路径 / 换文案）。
- 进阶效果（实测，五种都能出图，见 `designs/lettering-lab/effects-sheet.png`）：
  `type.pathOptions {effect:"rainbow|skew|3dRibbon|stairStep|gravity", start,end,spacing,alignToPath}`
  ——rainbow 沿弧面转折、skew 斜切基线、3dRibbon 卷曲、stairStep 阶梯、gravity 向路径压坠。
- 想改路径本身又保留排字：`text.reshapePath {id,anchors:[[subpath,anchor]…],dx,dy}`（未实测）。

### 5. 封套变形 / 局部扭曲（实测）

```json
{"command":"object.envelope.makeWithWarp","params":{"ids":[9],"style":"arc","bend":-30,"h":0,"v":0}}
```

- `style`：`arc | arcLower | arcUpper | arch | bulge | shellLower | shellUpper | flag | wave | fish | rise | fisheye | inflate | squeeze | twist`。
- `bend` 是主方向弯曲百分比（-100..100），`h/v` 是横/纵附加扭曲。
- 文字会变成 `Envelope` 对象，里面仍是可编辑的 Type；要定型就 `object.envelope.expand`（未实测）。
- 更狠的局部变形：`object.puppetWarp`（钉点 + 目标点 + 角度，as-rigid-as-possible）——
  实测可把整词按钉点位移/旋转（`designs/lettering-lab/puppet-demo.png`），钉点要落在字形范围内；
  做「只弯一笔」时把钉点加密在那一笔上，并给 `angles` 控制绕钉旋转（`rest:true` 可保存钉点）。
- 用形状当封套：`object.envelope.makeWithTopObject {ids}`——最上层的路径决定其他对象的形变（未实测）。

### 6. 图像 / 渐变填充（实测）

**图像填充（clipping mask）**：

```json
{"command":"file.place","params":{"path":"designs\\assets\\mountain-dusk.png","rect":[-700,-120,2025,1350]}},
{"command":"text.create","params":{"x":200,"y":1000,"text":"山","size":640,"font":"Alibaba PuHuiTi","style":"Heavy","color":"#141414"}},
{"command":"object.clippingMask.make","params":{"ids":[3,4]}},
{"command":"paint.setStroke","params":{"ids":[4],"color":"#D7261E"}},
{"command":"stroke.set","params":{"ids":[4],"weight":2}}
```

- **顺序不能反**：先置图，再建字（字在最上层），最后 `clippingMask.make {ids:[图, 字]}`。
  最上层的字变成裁切路径、失去填充，图像从字里透出来。
- 图像必须**盖满整个字形**。`file.place` 的 `rect` 是「等比缩放到框内」，不是裁切填充——
  图比字矮时，字的上下会露出空白。解决：把 `rect` 放大到比字大（本例图 3:2，框宽给到 2025）。
- 描边要在**蒙版之后**再设：蒙版前设的描边会丢（实测）。描边属于裁切路径，会画在图像之上。
- 也可以先给文字一个渐变（`paint.setFill` + `gradient`），渐变对 Type 是**文字空间**的，
  换字号不会重算位置。

### 7. 混合与重复（实测）

- `object.blend.make {ids:[A, Z], steps}` 让两个字形之间长出过渡形状与颜色（实测 A→Z 可出 6 步，
  见 `designs/lettering-lab/blend-demo.png`）；把中间某一步 `object.blend.expand` 取出来单独用，就有了「正在变形」的字。
- `object.transformEach {rotate, scaleH, random:true, seed:n}` 做可控的随机错位/旋转（实测 5 个矩形同 seed 可复现）；
  同一 seed 重跑结果一致，适合做序列海报。
- `object.createObjectMosaic` 把图像变成色块网格，再当字内纹理。

---

## 三、配方：三个可直接抄的场景

### A. 展览主标题：单字图内填充（`designs/lettering-lab/shan-type/`）

1. A4+ 竖版 / 1080×1350，纸色底。
2. 图像铺满：`file.place` 的 `rect` 给到 `[-700,-120,2025,1350]`（比字大）。
3. 单字：`text.create` 640pt，重黑，基线 y=1000。
4. `object.clippingMask.make {ids:[图,字]}`。
5. 蒙版后加 2pt 红描边（`paint.setStroke` + `stroke.set`）。
6. 上方标题 34pt 宋体 + 10pt 英文 + 0.5pt 横线；下方日期/地点 10–12pt；右下 64pt 红印章。

### B. 字形样本海报：五种变形同框（`designs/lettering-lab/`）

1. 主字 640pt + 红偏移副本（+14,+14）→ 渐变（`gradient` 字内空间）。
2. 第二字 250pt 只留描边，转 -8°。
3. 一条弧线路径 + 路径文字 22pt。
4. 一个词做 `envelope.makeWithWarp`（arc/wave）。
5. 一个字母转曲后 `path.moveAnchor` 改一笔。
6. 底部 legend 把五种手法编号列出——**把技术做成版面内容**，而不是藏在角落。

### C. 社媒标题：逐字错位（最便宜的高级感）

- 每个字独立 `text.create`，共同基线；交替 ±2° 旋转、±6pt 基线错位。
- 只给一个字上强调色；其余同色。
- 字距靠手动 x 偏移（中文 0～+20pt），不要用 tracking 硬拉（大字号下会散）。

---

## 四、字体与版权（硬门槛）

1. **只动许可允许动的字体**：OFL / Apache / 明确「免费商用」的字体可以转曲、改字形、用于 logo 与印刷品。
   商业字体（汉仪/方正/造字工房等）默认不转曲改形；**用户能出示该字体的商用授权**（授权书/订单/官方许可页）时，
   可以改造，并在 `CREDITS.md` 记录授权方、授权范围与凭证编号。拿不出授权就换 OFL 字体或手绘路径。
2. **OFL 的保留字体名（Reserved Font Name）**：改了字形又对外分发「字体文件」时，必须改名；
   只出海报/logo/图片不受影响。交付说明写清「基于 X 字体改造，OFL-1.1」。
3. **不要把改造后的字再当字体卖/送**，也不要在成品里声称「原创字体」。
4. **AI 生图不做最终文字**：模型写不对中文/多字；只用来做纹理、背景、氛围，文字层永远由矢量/字体生成。
5. 字的来源与许可写进 `CREDITS.md`（字体名 + 版本 + 许可 + 是否改造）。

---

## 五、工艺默认值（可以打破，只要你知道代价）

1. **默认一个主变形 + 一个辅助。** 想叠更多就叠——条件是每一层都能说出它在干什么，
   且叠完焦点还在、层级没塌。叠三种以上时，至少把其中一层做成**结构**（影响阅读顺序），别全是滤镜。
2. **可读性默认优先。** 主标题 ≤ 8 个汉字 / ≤ 3 个英文词，缩略图下认得出来；
   要做成抽象图形也行，配一行小字或说明，别让观众猜。
3. **光学对齐**：圆形字母（O/C/G）上下要溢出 1–2%，尖角（A/V）要探出，标点要悬挂；
   机器对齐在字艺里看起来就是「差一点」。
4. **与版面同源**：字形的角度、粗细、圆角、切口，要和网格/图形/图片的语汇一致；
   一张瑞士网格海报里放一个 3D 气球字，就是两种设计打架。
5. **留白给字让路**：字形越复杂，周围留白越大；字内填图时，背景必须安静。
6. **可编辑性**：交付时给 `.vcraft` 源文件 + 转曲说明；改稿要保留原始字（隐藏层或 `-type` 副本），
   否则下一版只能重画。

---

## 六、静默失败清单（实测踩出来的）

1. **`paint.setFill` / `paint.setStroke` 不带 `ids` 会改「当前选中 + 新画默认」**。
   刚画完的矩形还选中着，这时设默认色会把**它**改掉——必须写 `ids`，或先 `select.none {}`。
2. **`text.create` 返回的 `bounds` 不是字形框**：它含行高/上伸部。要做精确构图，先转曲再
   `document.inspect` 拿真实 bounds，或用 `object.align`。
3. **转曲会消耗 id**：文字 id=N → Compound=N+1、外轮廓=N+2、内孔=N+3、Group=N+4。
   后面的命令引用错一位，就会「改了个寂寞」。
4. **蒙版顺序**：图在下、字在上；`clippingMask.make {ids:[图,字]}`；描边在蒙版**之后**加。
5. **`file.place` 是等比装进 rect，不裁切**。图填字时 rect 要给大，否则字露白。
6. **JSON 步骤文件必须 UTF-8 无 BOM**。PowerShell 的 `Set-Content -Encoding UTF8`（5.1）会写 BOM，
   VectorCraft 直接报 `EOF while parsing`。用 `[IO.File]::WriteAllText(..., UTF8Encoding($false))`。
7. **每个 headless 进程都是新会话**：id 从 1 开始按创建顺序分配，跨文件/跨次调用不可复用。
8. **返回值 null 不代表没执行**：`path.reshape` / `path.moveAnchor` 成功也返回 null，必须渲染确认。
9. **`object.transformEach` 不改填充**：对象和底色同色时，变换了也「看不见」；先给色再看效果。
10. **`object.blend` 能直接吃文字**（实测 A→Z 六步），但两端字重/字宽差太大时，中间步会糊成一团；
    想让过渡干净，先用同一字族、只变字号/颜色。

---

## 七、交付前字形检查（若这单做了字形改造）

- [ ] 主标题的字形处理能用一句话说清（「把山的第三笔拉长成地平线」），不是「加了个效果」。
- [ ] 每一层效果都有作用；叠了几层是你选的，不是手滑的。
- [ ] 缩略图下可读，或已明确做成抽象图形并配小字。
- [ ] 字形与版面共用色板、角度、粗细语汇；没有第三种风格混入。
- [ ] 字内填图时，图像对比度足够；描边/留白把字与背景分开。
- [ ] 转曲前默认留了原始字（隐藏层或 `-type` 副本）；若用户明确不要，交付说明写了「已转曲、不可逆」。
- [ ] 字体许可允许改造；`CREDITS.md` 写了字体名、版本、许可、改造说明。
- [ ] 渲染图自己看过至少一次（含局部放大），不是只看 CLI 的 success。
