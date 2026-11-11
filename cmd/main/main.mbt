///|
/// ofdkit command line interface.
///
///   ofdkit demo <file.ofd> [font.ttf]   write a demonstration document
///   ofdkit verify <file.ofd>            re-read the package and check its structure
///   ofdkit info <file.ofd>              print a short summary
///   ofdkit font-info <font.ttf>         print basic facts about a font file
///
/// The CLI exists so the library has a runnable, reproducible example that can
/// be checked in CI without any editor or viewer installed.

///|
fn usage() -> Unit {
  println("ofdkit — OFD（GB/T 33190-2016）文档生成与校验")
  println("")
  println("用法:")
  println(
    "  ofdkit demo <file.ofd> [font.ttf]  生成示例文档，可选嵌入 TrueType 字体",
  )
  println("  ofdkit verify <file.ofd>           校验已有文档的结构")
  println("  ofdkit info <file.ofd>             打印文档摘要")
  println("  ofdkit font-info <font.ttf>        查看字体基本信息")
  println(
    "  ofdkit measure <font.ttf> <size> <text>  计算文本宽度（毫米）",
  )
}

///|
/// Every string the demo draws. Kept in one place so the embedded font subset
/// covers exactly the characters the document uses.
let demo_texts : Array[String] = [
  "ofdkit", "OFD 文档生成器", "纯 MoonBit 实现 · 符合 GB/T 33190-2016",
  "本文档由 ofdkit 生成，用于验证包结构、文本对象与图形对象。",
  "文本支持中文与 ASCII 混排，图形支持直线与矩形。", "第二页",
  "多页文档中每一页拥有独立的 Content.xml。", "项目", "说明", "容器",
  "ZIP，入口 OFD.xml", "内容", "XML 内容流，单位毫米", "RGB 填充示例",
]

///|
fn demo_corpus() -> String {
  let out = StringBuilder()
  for text in demo_texts {
    out.write_stringview(text)
  }
  out.to_string()
}

///|
/// Build a two-page demonstration document that exercises text, paths and
/// colour fills.
fn build_demo(doc : @ofdkit.Document) -> Unit {
  // Page 1 — cover.
  let page = doc.add_page()
  page.fill_rect(0.0, 0.0, 210.0, 40.0, @ofdkit.Color::new(24, 64, 140))
  page.text(20.0, 18.0, 8.0, demo_texts[0])
  page.text(20.0, 52.0, 12.0, demo_texts[1])
  page.text(20.0, 70.0, 6.0, demo_texts[2])
  page.line(20.0, 80.0, 190.0, 80.0, 0.4)
  // One wrapped paragraph instead of two hand-placed lines: the page measures
  // the text with the embedded font and breaks it at 170 mm.
  ignore(
    page.paragraph(
      20.0,
      95.0,
      170.0,
      5.0,
      7.0,
      demo_texts[3] + demo_texts[4],
    ),
  )
  // A simple table drawn with paths.
  page.rect(20.0, 120.0, 170.0, 40.0, 0.3)
  page.line(20.0, 133.0, 190.0, 133.0, 0.2)
  page.line(20.0, 146.0, 190.0, 146.0, 0.2)
  page.line(80.0, 120.0, 80.0, 160.0, 0.2)
  page.text(24.0, 124.0, 4.5, demo_texts[7])
  page.text(84.0, 124.0, 4.5, demo_texts[8])
  page.text(24.0, 137.0, 4.5, demo_texts[9])
  page.text(84.0, 137.0, 4.5, demo_texts[10])
  page.text(24.0, 150.0, 4.5, demo_texts[11])
  page.text(84.0, 150.0, 4.5, demo_texts[12])
  // Colour swatches.
  page.fill_rect(20.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(220, 60, 60))
  page.fill_rect(55.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(60, 160, 90))
  page.fill_rect(90.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(70, 110, 210))
  page.text(20.0, 196.0, 4.0, demo_texts[13])
  // Page 2 — proves the page list and BaseLoc wiring.
  let page2 = doc.add_page()
  page2.text(20.0, 30.0, 8.0, demo_texts[5])
  page2.text(20.0, 45.0, 5.0, demo_texts[6])
  page2.line(20.0, 55.0, 120.0, 55.0, 0.3)
  ()
}

///|
fn read_font(path : String) -> Bytes? {
  Some(@fs.read_file_to_bytes(path)) catch {
    @fs.IOError(message) => {
      println("字体读取失败: \{message}")
      None
    }
  }
}

///|
fn cmd_demo(path : String, font_path : String?) -> Unit {
  let doc = @ofdkit.Document::new()
    .set_title("ofdkit 示例文档")
    .set_author("ofdkit")
    .set_subject("OFD 生成器最小可用示例")
    .set_keywords("OFD,GB/T 33190,版式文档")
    .set_doc_id("ofdkit-demo-0001")
    .set_creation_date("2026-11-11")
  let mut font_note = "未嵌入字体"
  match font_path {
    None => ()
    Some(font_file) =>
      match read_font(font_file) {
        None => ()
        Some(bytes) =>
          match doc.embed_font_for_text("SimHei", bytes, demo_corpus()) {
            Err(message) => println("字体子集化失败: \{message}")
            Ok(font_id) => font_note = "嵌入字体 id=\{font_id}"
          }
      }
  }
  build_demo(doc)
  let bytes = doc.to_bytes()
  try {
    @fs.write_bytes_to_file(path, bytes)
    println(
      "已生成 \{path}（\{bytes.length()} 字节，\{doc.page_count()} 页，\{font_note}）",
    )
  } catch {
    @fs.IOError(message) => println("写入失败: \{message}")
  }
}

///|
fn cmd_verify(path : String) -> Unit {
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => {
      println("读取失败: \{message}")
      return
    }
  }
  let report = @ofdkit.verify_ofd(bytes)
  println("校验 \{path}")
  for check in report.checks {
    let mark = if check.passed { "  通过" } else { "  失败" }
    let detail = if check.detail == "" { "" } else { "  (\{check.detail})" }
    println("\{mark}  \{check.name}\{detail}")
  }
  println("")
  println(report.summary())
  if !report.passed() {
    println("结构校验未通过")
  }
}

///|
fn cmd_info(path : String) -> Unit {
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => {
      println("读取失败: \{message}")
      return
    }
  }
  match @ofdkit.parse_zip(bytes) {
    Err(message) => println("不是可读的 OFD 包: \{message}")
    Ok(archive) => {
      println("文件: \{path}")
      println("大小: \{bytes.length()} 字节")
      println("条目: \{archive.names().length()}")
      for name in archive.names() {
        println("  \{name}")
      }
    }
  }
}

///|
fn cmd_font_info(path : String) -> Unit {
  match read_font(path) {
    None => ()
    Some(bytes) =>
      match @ofdkit.parse_ttf(bytes) {
        Err(message) => println("字体解析失败: \{message}")
        Ok(face) => {
          println("文件: \{path}")
          println("大小: \{bytes.length()} 字节")
          println("表数: \{face.table_count()}")
          println("字形数: \{face.num_glyphs()}")
          println("unitsPerEm: \{face.units_per_em()}")
        }
      }
  }
}

///|
fn cmd_measure(font_path : String, size_text : String, text : String) -> Unit {
  let size = match @ofdkit.parse_double(size_text) {
    None => {
      println("字号无法解析: \{size_text}")
      return
    }
    Some(value) => value
  }
  match read_font(font_path) {
    None => ()
    Some(bytes) =>
      match @ofdkit.parse_ttf(bytes) {
        Err(message) => println("字体解析失败: \{message}")
        Ok(face) => {
          let upem = face.units_per_em()
          let mut units = 0
          for ch in text {
            let glyph = face.glyph_for_char(ch.to_uint().reinterpret_as_int())
            units = units + face.advance_width(glyph)
          }
          let width = units.to_double() / upem.to_double() * size
          println("\{width}")
        }
      }
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 3 {
    usage()
    return
  }
  let command = args[1]
  let path = args[2]
  match command {
    "demo" => {
      let font_path = if args.length() >= 4 { Some(args[3]) } else { None }
      cmd_demo(path, font_path)
    }
    "verify" => cmd_verify(path)
    "info" => cmd_info(path)
    "font-info" => cmd_font_info(path)
    "measure" => {
      if args.length() < 5 {
        println("用法: ofdkit measure <font.ttf> <size> <text>")
        return
      }
      cmd_measure(path, args[3], args[4])
    }
    _ => {
      println("未知命令: \{command}")
      println("")
      usage()
    }
  }
}
