///|
/// ofdkit command line interface.
///
///   ofdkit demo <file.ofd>     write a demonstration document
///   ofdkit verify <file.ofd>   re-read the package and check its structure
///   ofdkit info <file.ofd>     print a short summary
///
/// The CLI exists so the library has a runnable, reproducible example that can
/// be checked in CI without any editor or viewer installed.

///|
fn usage() -> Unit {
  println("ofdkit — OFD（GB/T 33190-2016）文档生成与校验")
  println("")
  println("用法:")
  println("  ofdkit demo <file.ofd>     生成示例文档")
  println("  ofdkit verify <file.ofd>   校验已有文档的结构")
  println("  ofdkit info <file.ofd>     打印文档摘要")
}

///|
/// Build a two-page demonstration document that exercises text, paths and
/// colour fills.
fn build_demo() -> @ofdkit.Document {
  let doc = @ofdkit.Document::new()
    .set_title("ofdkit 示例文档")
    .set_author("ofdkit")
    .set_subject("OFD 生成器最小可用示例")
    .set_keywords("OFD,GB/T 33190,版式文档")
    .set_doc_id("ofdkit-demo-0001")
    .set_creation_date("2026-11-11")
  // Page 1 — cover.
  let page = doc.add_page()
  page.fill_rect(0.0, 0.0, 210.0, 40.0, @ofdkit.Color::new(24, 64, 140))
  page.text(20.0, 18.0, 8.0, "ofdkit")
  page.text(20.0, 52.0, 12.0, "OFD 文档生成器")
  page.text(20.0, 70.0, 6.0, "纯 MoonBit 实现 · 符合 GB/T 33190-2016")
  page.line(20.0, 80.0, 190.0, 80.0, 0.4)
  page.text(
    20.0, 95.0, 5.0, "本文档由 ofdkit 生成，用于验证包结构、文本对象与图形对象。",
  )
  page.text(
    20.0, 104.0, 5.0, "文本支持中文与 ASCII 混排，图形支持直线与矩形。",
  )
  // A simple table drawn with paths.
  page.rect(20.0, 120.0, 170.0, 40.0, 0.3)
  page.line(20.0, 133.0, 190.0, 133.0, 0.2)
  page.line(20.0, 146.0, 190.0, 146.0, 0.2)
  page.line(80.0, 120.0, 80.0, 160.0, 0.2)
  page.text(24.0, 124.0, 4.5, "项目")
  page.text(84.0, 124.0, 4.5, "说明")
  page.text(24.0, 137.0, 4.5, "容器")
  page.text(84.0, 137.0, 4.5, "ZIP，入口 OFD.xml")
  page.text(24.0, 150.0, 4.5, "内容")
  page.text(84.0, 150.0, 4.5, "XML 内容流，单位毫米")
  // Colour swatches.
  page.fill_rect(20.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(220, 60, 60))
  page.fill_rect(55.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(60, 160, 90))
  page.fill_rect(90.0, 175.0, 30.0, 12.0, @ofdkit.Color::new(70, 110, 210))
  page.text(20.0, 196.0, 4.0, "RGB 填充示例")
  // Page 2 — second page proves the page list and BaseLoc wiring.
  let page2 = doc.add_page()
  page2.text(20.0, 30.0, 8.0, "第二页")
  page2.text(
    20.0, 45.0, 5.0, "多页文档中每一页拥有独立的 Content.xml。",
  )
  page2.line(20.0, 55.0, 120.0, 55.0, 0.3)
  doc
}

///|
fn cmd_demo(path : String) -> Unit {
  let doc = build_demo()
  let bytes = doc.to_bytes()
  try {
    @fs.write_bytes_to_file(path, bytes)
    println(
      "已生成 \{path}（\{bytes.length()} 字节，\{doc.page_count()} 页）",
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
fn main {
  let args = @env.args()
  if args.length() < 3 {
    usage()
    return
  }
  let command = args[1]
  let path = args[2]
  match command {
    "demo" => cmd_demo(path)
    "verify" => cmd_verify(path)
    "info" => cmd_info(path)
    _ => {
      println("未知命令: \{command}")
      println("")
      usage()
    }
  }
}
