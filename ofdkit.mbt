//! ofdkit — OFD（GB/T 33190-2016）版式文档生成器与结构校验器。
//!
//! 这个包只做两件事：
//!
//! 1. 把一个文档模型写成合法的 OFD 包（ZIP + XML 内容流）；
//! 2. 用独立的解析路径，校验自己产出的包结构是否自洽。
//!
//! ```mbt
//! let doc = Document::new().set_title("示例")
//! let page = doc.add_page()
//! page.text(20.0, 30.0, 5.0, "你好，OFD")
//! let bytes = match doc.to_bytes() {
//!   Ok(bytes) => bytes
//!   Err(message) => abort(message)
//! }
//! ```
//!
//! 坐标单位统一为毫米，原点在页面左上角，Y 轴向下，与标准一致。
//!
//! 已知边界：不读取也不渲染 OFD；不实现电子签章；字体只支持 TrueType 轮廓
//! （`.ttf`），不支持 CFF/OTF 与 TTC；不实现 GSUB/GPOS、渐变与透明度。
//! 完整列表见 README 的「现在不能做什么」。
