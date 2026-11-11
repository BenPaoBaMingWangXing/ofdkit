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

项目面向需要在 MoonBit 中产出固定版式文档的后端服务作者、政务与企业系统的国产化迁移团队，以及需要结构化生成文档的 AI 代理。提供文档模型、ZIP 打包、XML 内容流序列化、TrueType 字体子集化与嵌入、图片资源、表格排版、文档大纲，以及一套能独立校验自己产出的结构校验器。库包不依赖任何第三方库，ZIP 容器、XML 发射、CRC-32、TrueType 解析与子集化均为自写实现。

## 核心功能范围

- 提供 OFD 包结构生成：ZIP 容器（含目录记录）、`OFD.xml` 入口、`Doc_0/Document.xml`、`Doc_0/PublicRes.xml`、`Doc_0/DocumentRes.xml`、每页 `Pages/Page_N/Content.xml`
- 提供文档模型与单位约定：毫米坐标、原点在页面左上角、Y 轴向下，与标准一致
- 支持多页文档，默认 A4（210×297 mm），支持自定义页面尺寸
- 支持文本对象：中文与 ASCII 混排、字号、填充颜色、单行绘制
- 支持图形对象：直线、矩形、填充矩形、自定义路径（`M` / `L` / `C` / `Q` / `B` 指令）
- 支持 TrueType 字体解析：表目录、`head`、`maxp`、`hhea`、`hmtx`、`cmap`（format 4 / 12）、`loca`、`glyf`
- 支持字体子集化：按文档字符集取字形、复合字形闭包、字形重编号、重建 `loca` / `hmtx` / `maxp` / `cmap` / `post`
- 支持字体嵌入：子集写入 `Doc_0/Res/Font_N.ttf`，在 `PublicRes.xml` 中声明
- 支持基于真实字形的文本度量（`hmtx` advance width ÷ unitsPerEm × 字号）与自动换行，宽度与 FreeType 逐值一致
- 支持图片资源：PNG / JPEG 原样打包并在 `DocumentRes.xml` 声明，按毫米框定位
- 支持表格：`TableStyle` 列宽驱动、表头底色、网格线、单元格超宽截断补省略号
- 支持跨页表格：按页面剩余空间自动加页，续页重复表头
- 支持水平对齐：左 / 中 / 右
- 支持文档大纲：书签树，`Goto` 动作指向页面 ID
- 提供结构校验器 `verify_ofd`：独立读取路径（中央目录 → 本地头 → 数据），16 项检查，覆盖包结构、页面引用、资源存在性、对象 ID 上限、字体可解析性、图片格式、大纲目标
- 提供 CLI：`demo`（生成示例，可带字体与图片）、`verify`、`info`、`font-info`、`measure`
- 提供独立的外部校验脚本 `scripts/verify_ofd.py`，仅用 Python 标准库，与 MoonBit 代码零共享
- 提供预览渲染器 `scripts/preview_ofd.py`，把生成的 `.ofd` 渲染成 PNG，便于人工检查版面
- 提供不少于 60 个 MoonBit 测试（当前 67 个），覆盖 CRC-32 标准向量、ZIP 结构、XML 转义、序列化输出、包校验、TrueType 解析、子集化、文本度量、表格几何、大纲解析，并包含负例（截断归档、缺页面流、字体文件不是字体、图片魔数不对、大纲指向不存在的页）
- 提供 GitHub Actions 持续集成：构建、测试、生成示例、自校验、独立结构校验、字体路径、图片路径共 12 个步骤
- 提供 README 示例，覆盖最小文档生成、字体嵌入、表格与跨页、大纲、图片资源、CLI 全部子命令
- 提供 `docs/DEVLOG.md`、`CHANGELOG.md`、`NOTICE` 与 `LICENSE`（Apache-2.0）

## 本期不包含的功能

明确写出边界，避免验收时对 Scope 有分歧：

- **不读取、不渲染 OFD**。这是阅读器的职责，ofdkit 只做生成侧，没有版面解析与栅格化能力。
- **不实现电子签章（GB/T 38540）**。需要 SM2 椭圆曲线、ASN.1 DER、国密证书链与印模格式，工作量约等于现有全部功能之和；开发环境没有国密证书与验签工具，实现后无法验证。宁可不做，也不输出假签名。
- **ZIP 只写 store 模式**，不写 deflate。字体子集已压到 18 KB，整包 35 KB，引入压缩依赖的收益不足以抵消构建风险。
- **不支持两端对齐、字间距、英文断词回溯**。换行按字符宽度累加，英文单词只在整词超宽时才被拆开。
- **字体仅支持 BMP 码点**（`cmap` format 4）。生僻字与 emoji 不在子集内。

## 技术方案

```
业务数据
   ↓  Document / Page API（毫米坐标）
文档模型
   ↓  序列化
XML（OFD.xml / Document.xml / PublicRes.xml / DocumentRes.xml / Content.xml）
   ↓  ZIP 打包（自研容器，store 模式，时间戳固定以保证可复现）
xxx.ofd
```

三层验证，彼此独立：

1. `ofdkit verify`：读自己写出的包，但走完全独立的代码路径，不复用写入侧函数
2. `scripts/verify_ofd.py`：Python 标准库 `zipfile` + `ElementTree`，与 MoonBit 代码零共享
3. FreeType（经 Pillow）渲染子集字体，比对字形与原始字体的墨迹重合度

关键实现选择：

- **库包零第三方依赖**。ZIP 容器约 330 行、TrueType 解析与子集化约 760 行、XML 发射器约 130 行、CRC-32 约 70 行，全部自写。理由是构建可复现性。
- **写入与校验代码分离**。避免"用同一个 bug 验证自己"。
- **字形重编号式子集**。保留 glyph id 的稀疏方案只能到 134 KB，重编号后 18 KB。

## 验收判据

每条都可机器验证，不依赖主观判断：

1. `moon test` 全部通过（当前 67 个）
2. `moon build --target wasm` 与 `--target js` 均成功
3. `moon run cmd/main -- demo` 能生成 `.ofd` 文件
4. `moon run cmd/main -- verify` 报告 16/16 通过
5. `python3 scripts/verify_ofd.py` 退出码为 0，并报告页数、字体、图片、大纲
6. GitHub Actions 全绿（含字体路径与图片路径两条额外分支）
7. `mooncakes.io` 上可 `moon add BenPaoBaMingWangXing/ofdkit`，装包后能构建并生成合法文档

## 与参考实现的一致性验证

| 验证对象 | 方法 | 结果 |
|---|---|---|
| 包结构 | 与 ofdrw（MIT，1.9k stars）的 `helloworld.ofd` 逐项比对 | 修正了缺失的目录记录与 `CommonData` 元素顺序 |
| ZIP 容器 | Python `zipfile.testzip()` + 逐条目 CRC | 通过 |
| XML | `ElementTree` 按 `http://www.ofdspec.org/2016` 命名空间解析 | 四个部件全部可解析 |
| 文本度量 | FreeType `getlength` 对表（size=100） | `OFD 文档生成器` 700/700、`中文` 200/200、`ABCabc123` 450/450 |
| 字形渲染 | 二值化墨迹 IoU 对比原字体 | 160 px 0.977、80 px 0.932、40 px 0.869（差异来自丢弃的 hinting） |
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
| 11 月内 | 收集外部试用反馈，用真实 OFD 阅读器补一次兼容性实测 | 进行中 |
| 12 月 | 票据与报表类示例工程 | 计划 |
| 1 月 | 季度评选材料整理 | 计划 |

## 开源合规

- 许可证 Apache-2.0，含完整 `LICENSE`
- `NOTICE` 声明第三方归属：`moonbitlang/x`（Apache-2.0，仅 CLI 使用）、ofdrw（MIT，仅开发期结构比对，未复制代码）、开发期使用的系统字体（未随仓库分发）
- 原创性说明：所有 MoonBit 代码为本项目编写；ZIP、CRC-32、TrueType 相关算法知识来自公开格式规范

## 已知限制

- **尚未用真实 OFD 阅读器打开过**。开发环境既没有安装阅读器，也没有 JRE 跑 ofdrw，所以当前最强证据是"与 ofdrw 产物结构对齐"，这不等于"所有阅读器都能打开"。这是下一步最该补的验证。
- 字体子集丢失 hinting，小字号下的抗锯齿细节与原始字体会有一两像素差异，字形轮廓一致。
- ZIP 不压缩，包体积偏大（35 KB 量级）。
- 表头样式固定为浅灰底，暂不支持自定义斑马纹与边框样式。
