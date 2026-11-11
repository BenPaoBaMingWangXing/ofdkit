# ofdkit 项目申报书

11 月 11 日

## 基本信息

- **项目名称**：ofdkit：纯 MoonBit 的 OFD 版式文档生成器与结构校验器
- **参赛者**：BenPaoBaMingWangXing
- **联系方式**：360018614@qq.com
- **GitHub 仓库链接**：<https://github.com/BenPaoBaMingWangXing/ofdkit>
- **项目方向**：MoonBit 版式文档基础库 / 国产基础软件基础设施
- **是否为移植项目**：否。按 GB/T 33190-2016 标准原创实现，未移植其他语言的代码

## 项目简介

ofdkit 把国家标准 GB/T 33190-2016 定义的 OFD 版式文档格式的**生成能力**做进 MoonBit 生态。OFD 是电子发票、电子档案、电子证照等场景中国产替代 PDF 的版式文档格式，国内阅读器已有多个，但写入侧在 MoonBit 里是空白——业务系统要出报表、票据、公文，只能调外部进程或转 PDF。

项目面向需要在 MoonBit 中产出固定版式文档的后端服务作者、政务与企业系统的国产化迁移团队，以及需要结构化生成文档的 AI 代理。提供文档模型、ZIP 打包、XML 内容流序列化、TrueType 字体子集化与嵌入、图片资源、表格排版、段落对齐、文档大纲，以及一套能独立校验自己产出的结构校验器。库包不依赖任何第三方库，ZIP 容器、DEFLATE 编解码、XML 发射、CRC-32、TrueType 解析与子集化均为自写实现。

## 核心功能范围

- 提供 OFD 包结构生成：ZIP 容器（含目录记录）、`OFD.xml` 入口、`Doc_0/Document.xml`、`Doc_0/PublicRes.xml`、`Doc_0/DocumentRes.xml`、每页 `Pages/Page_N/Content.xml`
- 提供文档模型与单位约定：毫米坐标、原点在页面左上角、Y 轴向下，与标准一致
- 支持多页文档，默认 A4（210×297 mm），支持自定义页面尺寸
- 支持文本对象：中文与 ASCII 混排、字号、填充颜色、单行绘制、逐字定位
- 支持图形对象：直线、矩形、填充矩形、自定义路径（`M` / `L` / `C` / `Q` / `B` 指令）
- 支持 ZIP 压缩：自研 DEFLATE 编码器（RFC 1951，固定 Huffman + 哈希链 + 惰性匹配），可压缩条目按压缩存储，压缩后不划算的条目自动退回 store；`zipfile.testzip()` 与 ofdrw 均可正常解码
- 支持 TrueType 字体解析：表目录、`head`、`maxp`、`hhea`、`hmtx`、`cmap`（format 4 / 12）、`loca`、`glyf`
- 支持字体子集化：按文档字符集取字形、复合字形闭包、字形重编号、重建 `loca` / `hmtx` / `maxp` / `cmap` / `post`，并保留 hinting 三表（`cvt `/`fpgm`/`prep`）
- 支持字体嵌入：子集写入 `Doc_0/Res/Font_N.ttf`，在 `PublicRes.xml` 中声明
- 支持基于真实字形的文本度量（`hmtx` advance width ÷ unitsPerEm × 字号）与自动换行，宽度与 FreeType 逐值一致；英文断词会回溯到上一个空格
- 支持图片资源：PNG / JPEG 原样打包并在 `DocumentRes.xml` 声明，按毫米框定位
- 支持表格：`TableStyle` 列宽驱动，表头底色、斑马纹、边框颜色、内边距、行高、字号均可配置，单元格超宽截断补省略号
- 支持跨页表格：按页面剩余空间自动加页，续页重复表头
- 支持水平对齐：左 / 中 / 右 / 两端对齐；两端对齐按中文规范均摊字间距，且不会拆分拉丁词
- 支持字间距：`text_spaced` 逐字定位，`text_justified` 按框宽撑满
- 支持文档大纲：书签树，`Goto` 动作指向页面 ID
- 提供结构校验器 `verify_ofd`：独立读取路径（中央目录 → 本地头 → 数据），16 项检查，覆盖包结构、页面引用、资源存在性、对象 ID 上限、字体可解析性、图片格式、大纲目标
- 提供 CLI：`demo`（生成示例，可带字体与图片）、`verify`、`info`、`font-info`、`measure`
- 提供独立的外部校验脚本 `scripts/verify_ofd.py`，仅用 Python 标准库，与 MoonBit 代码零共享
- 提供预览渲染器 `scripts/preview_ofd.py`，把生成的 `.ofd` 渲染成 PNG，便于人工检查版面
- 提供第三方阅读器验证脚本 `scripts/java/ReadOfd.java`，用 ofdrw 真实读取生成的包并统计对象，方法记录在 `scripts/reader_check.md`
- 提供 91 个 MoonBit 测试，覆盖 CRC-32 标准向量、ZIP 结构、DEFLATE 往返、XML 转义、序列化输出、包校验、TrueType 解析、子集化、文本度量、表格几何、两端对齐、字间距、大纲解析，并包含负例（截断归档、缺页面流、字体文件不是字体、图片魔数不对、大纲指向不存在的页）
- 提供 GitHub Actions 持续集成：构建、测试、生成示例、自校验、独立结构校验、字体路径、图片路径共 12 个步骤
- 提供 README 示例，覆盖最小文档生成、字体嵌入、表格与跨页、两端对齐、字间距、大纲、图片资源、CLI 全部子命令
- 提供 `docs/DEVLOG.md`、`CHANGELOG.md`、`NOTICE` 与 `LICENSE`（Apache-2.0）

## 本期不包含的功能

明确写出边界，避免验收时对 Scope 有分歧：

- **不读取、不渲染 OFD**。这是阅读器的职责，ofdkit 只做生成侧，没有版面解析与栅格化能力。仓库里的 `preview_ofd.py` 只是预览脚本，不是渲染器。
- **不实现电子签章（GB/T 38540）**。需要 SM2 椭圆曲线、ASN.1 DER、国密证书链与印模格式，工作量约等于现有全部功能之和；开发环境没有国密证书与验签工具，实现后无法验证。宁可不做，也不输出假签名。
- **不实现 OpenType 高级排版**。`GSUB`/`GPOS` 不读也不用，竖排、连字、字距调整表都不生效。
- **不支持渐变、透明度、裁剪路径**。图形只有纯色描边与填充。
- **压缩只用固定 Huffman 单块**。比 zlib `-9` 差 6%~14%，动态 Huffman 的码长树构建与传输收益不足以抵消复杂度。
- **位图只认 PNG / JPEG**。JBIG2、CCITT G4、JPEG 2000 这类 OFD 允许的格式没有写入口。

## 技术方案

```
业务数据
   ↓  Document / Page API（毫米坐标）
文档模型
   ↓  序列化
XML（OFD.xml / Document.xml / PublicRes.xml / DocumentRes.xml / Content.xml）
   ↓  ZIP 打包（自研容器，固定 Huffman DEFLATE，时间戳固定以保证可复现）
xxx.ofd
```

五层验证，彼此独立：

1. `ofdkit verify`：读自己写出的包，但走完全独立的代码路径，不复用写入侧函数
2. `scripts/verify_ofd.py`：Python 标准库 `zipfile` + `ElementTree`，与 MoonBit 代码零共享
3. `zipfile.testzip()`：把 DEFLATE 条目交回 CPython 的 zlib 解码并校验 CRC
4. FreeType（经 Pillow）渲染子集字体，比对字形与原始字体的墨迹重合度
5. ofdrw（Java，MIT）：真实阅读器读取，核对页面数、对象数、页面尺寸与中文内容

关键实现选择：

- **库包零第三方依赖**。ZIP 容器 380 行、DEFLATE 编解码 520 行、TrueType 解析与子集化 990 行、XML 发射器 130 行、CRC-32 60 行，全部自写。理由是构建可复现性。
- **写入与校验代码分离**。避免"用同一个 bug 验证自己"。DEFLATE 的编码与解码确实是共用同一张距离码表，因此额外用 CPython `zlib` 做了外部对拍（第 3 层），并且在开发中靠它抓到了一个只在自洽解码下不暴露的码表错误。
- **字形重编号式子集**。保留 glyph id 的稀疏方案只能到 134 KB，重编号后 21 KB。

## 验收判据

每条都可机器验证，不依赖主观判断：

1. `moon test` 全部通过（当前 91 个）
2. `moon build --target wasm` 与 `--target js` 均成功
3. `moon run cmd/main -- demo` 能生成 `.ofd` 文件
4. `moon run cmd/main -- verify` 报告 16/16 通过
5. `python3 scripts/verify_ofd.py` 退出码为 0，并报告页数、字体、图片、大纲
6. `python3 -c "import zipfile; zipfile.ZipFile('out/demo.ofd').testzip()"` 返回 `None`
7. ofdrw 读取生成的包，页面数、对象数与中文内容与生成时一致
8. GitHub Actions 全绿（含字体路径与图片路径两条额外分支）
9. `mooncakes.io` 上可 `moon add BenPaoBaMingWangXing/ofdkit`，装包后能构建并生成合法文档

## 与参考实现的一致性验证

| 验证对象 | 方法 | 结果 |
|---|---|---|
| 包结构 | 与 ofdrw（MIT，1.9k stars）的 `helloworld.ofd` 逐项比对 | 修正了缺失的目录记录与 `CommonData` 元素顺序 |
| 真实读取 | ofdrw `ofdrw-reader` 2.5.1 解析生成的包 | 2 页、19 个文本对象（90 个 TextCode）、17 个图形对象、1 个图片对象，A4 尺寸与中文内容正确 |
| ZIP 容器 | Python `zipfile.testzip()` + 逐条目 CRC | 通过（含 deflate 条目） |
| DEFLATE 编码 | CPython `zlib.decompressobj(-15)` 解码自研输出 | 通过；压缩率 63.2%，zlib `-9` 为 58.6% |
| XML | `ElementTree` 按 `http://www.ofdspec.org/2016` 命名空间解析 | 四个部件全部可解析 |
| 文本度量 | FreeType `getlength` 对表（size=100） | `OFD 文档生成器` 700/700、`中文` 200/200、`ABCabc123` 450/450 |
| 字形渲染 | 二值化墨迹 IoU 对比原字体 | 160 / 80 / 40 / 20 px 均为 1.0000（hinting 保留后逐像素一致） |
| 对象 ID 上限 | 独立脚本检查 `MaxUnitID` 是否覆盖所有对象 ID | 修正过一次声明值偏小的问题 |

## 里程碑

| 时间 | 内容 | 状态 |
|---|---|---|
| 11 月 11 日 | 包结构、文本、图形、校验器、CLI（v0.1.1） | 完成 |
| 11 月 11 日 | 字体子集化与嵌入（v0.2.0） | 完成 |
| 11 月 11 日 | 真实度量与自动换行（v0.3.0） | 完成 |
| 11 月 11 日 | 图片资源（v0.4.0） | 完成 |
| 11 月 11 日 | 表格、对齐、预览渲染器（v0.5.0） | 完成 |
| 11 月 11 日 | 文档大纲（v0.6.0） | 完成 |
| 11 月 11 日 | 字形重编号、跨页表格、合规文件（v0.7.0） | 完成 |
| 11 月 11 日 | ZIP 压缩、两端对齐与字间距、表格样式、hinting 保留、ofdrw 实测（v0.8.0） | 完成 |
| 11 月内 | 收集外部试用反馈，补充票据场景样例 | 进行中 |
| 12 月 | 票据与报表类示例工程 | 计划 |
| 1 月 | 季度评选材料整理 | 计划 |

## 开源合规

- 许可证 Apache-2.0，含完整 `LICENSE`
- `NOTICE` 声明第三方归属：`moonbitlang/x`（Apache-2.0，仅 CLI 使用）、ofdrw（MIT，仅开发期结构比对与读取验证，未复制代码）、开发期使用的系统字体（未随仓库分发）、OpenJDK 与 ofdrw 的 jar 仅存在于本地 `_tools/`，不进仓库
- 原创性说明：所有 MoonBit 代码为本项目编写；ZIP、DEFLATE、CRC-32、TrueType 相关算法知识来自公开格式规范（RFC 1951、IEEE 802.3、OpenType 规范、GB/T 33190-2016）

## 已知限制

上一版列出的四条已全部关闭，这里是关闭方式与仍然存在的边界：

| 上一版的限制 | 现状 |
|---|---|
| 尚未用真实 OFD 阅读器打开过 | **已关闭**。下载 OpenJDK 17 + ofdrw 2.5.1，`ReadOfd.java` 成功读取 2 页、19 文本对象（90 TextCode）、17 图形对象、1 图片对象，中文与页面尺寸正确 |
| 字体子集丢失 hinting | **已关闭**。`cvt `/`fpgm`/`prep` 保留并重算校验和，FreeType 渲染的墨迹 IoU 从 0.869 提升到 1.0000 |
| ZIP 不压缩 | **已关闭**。自研 DEFLATE，整包 51,467 → 32,512 字节（63.2%），比 zlib `-9` 高 6% |
| 表头样式固定 | **已关闭**。`TableStyle` 支持斑马纹、边框颜色、内边距、行高、字号、表头底色 |

仍然存在的工程边界（都有明确理由，不是"没做完"）：

- **压缩率不是最优**。固定 Huffman 无法按字节频率自适应，字体这类分布平坦的数据差 14%。改成动态 Huffman 需要建树与码表传输，代码量翻倍而收益是个位数的 KB。
- **没有版面解析能力**。生成侧永远不知道自己的输出"长什么样"，只能靠外部渲染器看。
- **单线程、无流式输出**。整包在内存里拼装，适合单文档（MB 级），不适合批量生成十万张票据。
