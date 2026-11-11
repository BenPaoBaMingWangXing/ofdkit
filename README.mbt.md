# ofdkit

纯 MoonBit 实现的 **OFD 文档生成器与结构校验器**。

OFD（Open Fixed-layout Document，开放式版式文档）是国家标准 **GB/T 33190-2016** 定义的版式文档格式，在电子发票、电子档案、电子证照等场景中作为 PDF 的国产替代格式使用。ofdkit 让 MoonBit 程序可以直接生成 `.ofd` 文件，并用独立的解析路径校验自己产出的包结构。

```
JSON / 业务数据  →  ofdkit  →  xxx.ofd  →  OFD 阅读器
```

## 现在能做什么

- 生成符合标准包结构的 `.ofd` 文件（ZIP 容器 + `OFD.xml` 入口 + `Doc_0/Document.xml` + 每页 `Content.xml`）
- 多页文档，A4 或自定义页面尺寸
- 文本对象：中文与 ASCII 混排、字号、颜色
- 图形对象：直线、矩形、填充矩形、自定义路径（`M` / `L` / `C` / `Q` / `B` 指令）
- 字体资源声明（`PublicRes.xml`）
- 文档元数据：标题、作者、主题、关键词、创建日期
- 结构自校验：`ofdkit verify` 会重新解析生成的包，逐项检查必需文件与引用是否自洽

## 现在不能做什么

这些是已知缺口，不是"暂未测试"——代码里确实没有：

- **不读取、不渲染 OFD**。这是生成侧工具，没有版面解析和栅格化能力。
- **不嵌入字体文件**。`PublicRes.xml` 里目前只声明字体名（默认 `SimSun`），由阅读器按名替换。嵌入 TrueType 子集是下一阶段的工作。
- **不支持签章**。GB/T 38540 的电子签章（`Signatures.xml` / `Seal.esl` / `SignedValue.dat`）尚未实现。
- **不支持图片对象**（`ImageObject`）。
- **不支持自动换行、对齐、字间距**。文本按单行绘制，调用方给位置和宽度估算。
- **ZIP 只写 store 模式**（不压缩）。包体积因此偏大，但结构完全合法且可复现。

## 安装

```
moon add BenPaoBaMingWangXing/ofdkit
```

要求 MoonBit 工具链 `moon >= 0.1.20261023`。

## 快速开始

```mbt nocheck
///|
fn build_report() -> Bytes {
  let doc = @ofdkit.Document::new()
    .set_title("月度报表")
    .set_author("财务部")
  let page = doc.add_page() // A4, 210 x 297 mm
  page.text(20.0, 30.0, 10.0, "月度报表")
  page.line(20.0, 38.0, 190.0, 38.0, 0.4)
  page.text(20.0, 50.0, 5.0, "本期收入较上期增长 12.4%。")
  page.fill_rect(20.0, 60.0, 40.0, 8.0, @ofdkit.Color::new(24, 64, 140))
  doc.to_bytes()
}
```

坐标单位统一为**毫米**，原点在页面左上角，Y 轴向下——与标准一致，调用方不需要做任何单位换算。

## 命令行

```
moon run cmd/main -- demo   out/demo.ofd
moon run cmd/main -- verify out/demo.ofd
moon run cmd/main -- info   out/demo.ofd
```

`verify` 的实际输出：

```
校验 out/demo.ofd
  通过  zip container parses  (9 entries)
  通过  OFD.xml present  (at archive root)
  通过  OFD.xml declares ofd:OFD
  通过  DocRoot declared  (Doc_0/Document.xml)
  通过  DocRoot resolves  (Doc_0/Document.xml)
  通过  Document.xml declares ofd:Document
  通过  document declares a page box  (0 0 210 297)
  通过  document has pages  (2 page(s))
  通过  every page content stream exists
  通过  PublicRes resolves  (Doc_0/PublicRes.xml)
  通过  declared font files are packaged  (no embedded fonts)

11/11 checks passed
```

## 包结构

```
OFD.xml                         入口，指向 DocRoot
Doc_0/Document.xml              文档骨架、页面列表、共享资源引用
Doc_0/PublicRes.xml             字体等共享资源
Doc_0/Pages/Page_0/Content.xml  第 1 页内容流
Doc_0/Pages/Page_1/Content.xml  第 2 页内容流
```

内容流里的对象形如：

```xml
<ofd:TextObject ID="1000" Boundary="20 30 60 6" Font="2" Size="5" Fill="true">
  <ofd:FillColor Value="0 0 0"/>
  <ofd:TextCode X="0" Y="5">月度报表</ofd:TextCode>
</ofd:TextObject>
```

## 与成熟实现的结构对齐

[ofdrw](https://github.com/ofdrw/ofdrw)（OFD Reader & Writer，MIT，是目前使用最广的 OFD 实现）的测试样例 `helloworld.ofd` 被拿来逐项比对包结构。据此修正了两处偏差：

1. **ZIP 必须包含目录条目**（`Doc_0/`、`Doc_0/Pages/`、`Doc_0/Pages/Page_N/`），只写叶子文件是不够的——不少阅读器依赖目录记录遍历包；
2. **`CommonData` 的子元素顺序**为 `PageArea` → `PublicRes` → `MaxUnitID`；页面尺寸在 `Document.xml` 里声明一次，`Content.xml` 不再重复一层 `Area`。

这两处都是"按标准字面写合法"但"与事实实现不一致"的差异，自己的校验器发现不了——只有拿别人的产物对比才会暴露。

## 怎么证明它是对的

三层，都不依赖 ofdkit 自己：

1. **外部 ZIP 解析**：生成的文件用 Python 标准库 `zipfile` 打开，`testzip()` 通过，逐个条目 CRC 校验。
2. **外部 XML 解析**：四个 XML 用 `xml.etree.ElementTree` 解析，命名空间为 `http://www.ofdspec.org/2016`，可正确读出页面数、对象数、中文文本。
3. **自带结构校验**：`ofdkit verify` 走的是独立的 ZIP 读取路径（`parse_zip` → 中央目录 → 本地头 → 数据），不复用写入侧代码。

第三层在开发中真实抓到过一个 bug：`MaxUnitID` 原本直接取文档计数器，而页面对象 ID 是分段分配的，导致声明的最大 ID 小于实际对象 ID——违反标准，现已修正并由 `max unit id covers page object ids` 测试守住。

## 设计取舍

- **不引入 XML 库**：OFD 的 XML 结构浅且固定，手写发射器比通用 DOM 更可控，也便于保证转义不漏。
- **不引入 ZIP 库**：容器逻辑只有几百行，自己写换来零依赖和字节级可复现（时间戳固定为 ZIP 纪元）。
- **写入与校验代码分离**：校验器读自己的输出，但走完全不同的代码路径，避免"用同一个 bug 验证自己"。
- **对象 ID 分段**：每页从 `page_id * 1000` 起分配，避免页间冲突，也便于人工排查。

## 测试

```
moon test
```

24 个测试，覆盖 CRC-32 标准向量、ZIP 结构、XML 转义、序列化输出、包校验、负例（截断归档、缺页面流）。

## 路线图

- [ ] TrueType 子集化与字体嵌入（`FontFile` + CID 字体）
- [ ] 图片对象（PNG / JPEG）
- [ ] 自动换行与简单排版
- [ ] 文档大纲（`Outlines`）
- [ ] GB/T 38540 电子签章

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
