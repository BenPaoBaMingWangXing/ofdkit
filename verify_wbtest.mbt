///|
/// Tests for the reader and the structural verifier. These are the checks that
/// back the "可验证" claim in the README: a package we produce must survive a
/// round trip through an independent parser.

///|
test "zip reader round trips a stored entry" {
  let zw = ZipWriter::new()
  zw.add_file("OFD.xml", b"<ofd:OFD/>")
  zw.add_file("Doc_0/Document.xml", b"<ofd:Document/>")
  let archive = zw.finish()
  match parse_zip(archive) {
    Err(message) => fail("expected a readable archive, got \{message}")
    Ok(zip) => {
      assert_eq(zip.names().length(), 2)
      assert_true(zip.contains("Doc_0/Document.xml"))
      match zip.read("OFD.xml") {
        Err(message) => fail("expected payload, got \{message}")
        Ok(bytes) => assert_eq(@utf8.decode_lossy(bytes), "<ofd:OFD/>")
      }
    }
  }
}

///|
test "zip reader rejects a truncated archive" {
  let zw = ZipWriter::new()
  zw.add_file("OFD.xml", b"<ofd:OFD/>")
  let archive = zw.finish()
  let keep = archive.length() - 10
  let tmp = FixedArray::make(keep, b'\x00')
  for i in 0..<keep {
    tmp[i] = archive[i]
  }
  let short = Bytes::from_array(tmp[:])
  // Not a valid archive any more; parse must fail rather than panic.
  match parse_zip(short) {
    Err(_) => assert_true(true)
    Ok(_) => fail("a truncated archive should not parse")
  }
}

///|
test "verify accepts a well formed document" {
  let doc = Document::new().set_title("示例")
  let page = doc.add_page()
  page.text(20.0, 20.0, 5.0, "你好")
  let report = verify_ofd(pack(doc))
  assert_true(report.passed())
  assert_eq(report.failures().length(), 0)
}

///|
test "verify reports every check it ran" {
  let doc = Document::new()
  ignore(doc.add_page())
  let report = verify_ofd(pack(doc))
  assert_true(report.checks.length() >= 8)
  assert_true(report.summary().contains("checks passed"))
}

///|
test "verify rejects bytes that are not an archive" {
  let junk : Bytes = b"not an ofd file at all"
  let report = verify_ofd(junk)
  assert_false(report.passed())
}

///|
test "verify catches a package missing its page stream" {
  // Assemble a package by hand that claims a page but ships no content stream.
  let zw = ZipWriter::new()
  let ofd_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:OFD xmlns:ofd=\"http://www.ofdspec.org/2016\" DocType=\"OFD\" Version=\"1.1\"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>"
  let doc_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Document xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:Pages><ofd:Page ID=\"1\" BaseLoc=\"Pages/Page_0/Content.xml\"/></ofd:Pages></ofd:Document>"
  zw.add_file("OFD.xml", @utf8.encode(ofd_xml))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(doc_xml))
  let report = verify_ofd(zw.finish())
  assert_false(report.passed())
  assert_true(report.failures().length() > 0)
}

///|
test "max unit id covers page object ids" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text(10.0, 10.0, 4.0, "a")
  page.text(10.0, 20.0, 4.0, "b")
  let max = doc.max_unit_id()
  for obj in page.objects {
    let id = match obj {
      Text(t) => t.id
      Path(p) => p.id
      Image(i) => i.id
    }
    assert_true(max >= id)
  }
}

///|
test "verify rejects a package whose font file is not a font" {
  // Hand-build a package that declares a font and ships garbage bytes for it.
  let zw = ZipWriter::new()
  let ofd_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:OFD xmlns:ofd=\"http://www.ofdspec.org/2016\" DocType=\"OFD\" Version=\"1.1\"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>"
  let doc_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Document xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:CommonData><ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea><ofd:PublicRes>PublicRes.xml</ofd:PublicRes><ofd:MaxUnitID>4</ofd:MaxUnitID></ofd:CommonData><ofd:Pages><ofd:Page ID=\"1\" BaseLoc=\"Pages/Page_0/Content.xml\"/></ofd:Pages></ofd:Document>"
  let res_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Res xmlns:ofd=\"http://www.ofdspec.org/2016\" BaseLoc=\"Res\"><ofd:Fonts><ofd:Font ID=\"2\" FontName=\"SimHei\" FamilyName=\"SimHei\" Charset=\"unicode\"><ofd:FontFile>Font_2.ttf</ofd:FontFile></ofd:Font></ofd:Fonts></ofd:Res>"
  let page_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Page xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:Content><ofd:Layer ID=\"3\"/></ofd:Content></ofd:Page>"
  zw.add_file("OFD.xml", @utf8.encode(ofd_xml))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(doc_xml))
  zw.add_file("Doc_0/PublicRes.xml", @utf8.encode(res_xml))
  zw.add_file("Doc_0/Pages/Page_0/Content.xml", @utf8.encode(page_xml))
  zw.add_file("Doc_0/Res/Font_2.ttf", b"this is not a font file")
  let report = verify_ofd(zw.finish())
  assert_false(report.passed())
  let mut found = false
  for failure in report.failures() {
    if failure.name == "embedded fonts are readable" {
      found = true
    }
  }
  assert_true(found)
}

///|
fn push_u16(bytes : Array[Int32], value : Int32) -> Unit {
  bytes.push((value >> 8) & 0xFF)
  bytes.push(value & 0xFF)
}

///|
fn push_u32(bytes : Array[Int32], value : Int32) -> Unit {
  bytes.push((value >> 24) & 0xFF)
  bytes.push((value >> 16) & 0xFF)
  bytes.push((value >> 8) & 0xFF)
  bytes.push(value & 0xFF)
}

///|
fn push_tag(bytes : Array[Int32], tag : String) -> Unit {
  for ch in tag {
    bytes.push(ch.to_uint().reinterpret_as_int())
  }
}

///|
/// A two-glyph TrueType font whose `cmap` maps every code in `codes` to glyph 1.
/// Enough for the verifier to tell "this character is in the subset" apart from
/// "it is not", without shipping a real font file or depending on the host.
fn synthetic_font(codes : Array[Int32]) -> Bytes {
  let seg_count = codes.length() + 1
  let cmap : Array[Int32] = []
  push_u16(cmap, 0) // version
  push_u16(cmap, 1) // one encoding record
  push_u16(cmap, 3) // Windows
  push_u16(cmap, 1) // Unicode BMP
  push_u32(cmap, 12) // subtable offset
  push_u16(cmap, 4) // format
  push_u16(cmap, 16 + seg_count * 8) // byte length
  push_u16(cmap, 0) // language
  push_u16(cmap, seg_count * 2)
  push_u16(cmap, 1) // searchRange (unused by our reader)
  push_u16(cmap, 0) // entrySelector
  push_u16(cmap, 0) // rangeShift
  for code in codes {
    push_u16(cmap, code)
  }
  push_u16(cmap, 0xFFFF)
  push_u16(cmap, 0) // reservedPad
  for code in codes {
    push_u16(cmap, code)
  }
  push_u16(cmap, 0xFFFF)
  for code in codes {
    push_u16(cmap, (1 - code) & 0xFFFF)
  }
  push_u16(cmap, 1)
  for _ in codes {
    push_u16(cmap, 0)
  }
  push_u16(cmap, 0)

  let head : Array[Int32] = []
  push_u32(head, 0x00010000)
  push_u32(head, 0) // fontRevision
  push_u32(head, 0) // checkSumAdjustment
  push_u32(head, 0x5F0F3CF5) // magic
  push_u16(head, 0) // flags
  push_u16(head, 1000) // unitsPerEm
  push_u32(head, 0) // created
  push_u32(head, 0)
  push_u32(head, 0) // modified
  push_u32(head, 0)
  push_u16(head, 0) // xMin
  push_u16(head, 0) // yMin
  push_u16(head, 1000) // xMax
  push_u16(head, 1000) // yMax
  push_u16(head, 0) // macStyle
  push_u16(head, 8) // lowestRecPPEM
  push_u16(head, 2) // fontDirectionHint
  push_u16(head, 0) // indexToLocFormat: short
  push_u16(head, 0) // glyphDataFormat

  let hhea : Array[Int32] = []
  push_u32(hhea, 0x00010000)
  push_u16(hhea, 800) // ascender
  push_u16(hhea, -200 & 0xFFFF) // descender
  push_u16(hhea, 0) // lineGap
  push_u16(hhea, 1000) // advanceWidthMax
  push_u16(hhea, 0) // minLeftSideBearing
  push_u16(hhea, 0) // minRightSideBearing
  push_u16(hhea, 1000) // xMaxExtent
  push_u16(hhea, 1) // caretSlopeRise
  push_u16(hhea, 0) // caretSlopeRun
  push_u16(hhea, 0) // caretOffset
  push_u16(hhea, 0) // reserved
  push_u16(hhea, 0)
  push_u16(hhea, 0)
  push_u16(hhea, 0)
  push_u16(hhea, 0) // metricDataFormat
  push_u16(hhea, 2) // numberOfHMetrics

  let hmtx : Array[Int32] = []
  push_u16(hmtx, 1000)
  push_u16(hmtx, 0)
  push_u16(hmtx, 1000)
  push_u16(hmtx, 0)

  let maxp : Array[Int32] = []
  push_u32(maxp, 0x00010000)
  push_u16(maxp, 2) // numGlyphs
  for _ in 0..<13 {
    push_u16(maxp, 0)
  }

  let loca : Array[Int32] = []
  for _ in 0..<3 {
    push_u16(loca, 0)
  }

  let glyf : Array[Int32] = []
  let tables : Array[(String, Array[Int32])] = [
    ("cmap", cmap),
    ("glyf", glyf),
    ("head", head),
    ("hhea", hhea),
    ("hmtx", hmtx),
    ("loca", loca),
    ("maxp", maxp),
  ]
  let count = tables.length()
  let offsets : Array[Int32] = []
  let mut cursor = 12 + count * 16
  for i in 0..<count {
    offsets.push(cursor)
    cursor = cursor + tables[i].1.length()
    while cursor % 4 != 0 {
      cursor = cursor + 1
    }
  }
  let out : Array[Int32] = []
  push_u32(out, 0x00010000)
  push_u16(out, count)
  push_u16(out, 64) // searchRange
  push_u16(out, 2) // entrySelector
  push_u16(out, 48) // rangeShift
  for i in 0..<count {
    push_tag(out, tables[i].0)
    push_u32(out, 0) // checksum, our reader does not verify it
    push_u32(out, offsets[i])
    push_u32(out, tables[i].1.length())
  }
  for i in 0..<count {
    for byte in tables[i].1 {
      out.push(byte)
    }
    while out.length() % 4 != 0 {
      out.push(0)
    }
  }
  bytes_from(out)
}

///|
test "a character outside the subset fails the coverage check" {
  let doc = Document::new()
  // The subset knows 'A' only.
  let font_id = doc.add_embedded_font("Synth", synthetic_font([0x41]))
  let page = doc.add_page()
  ignore(page.text_with_font(20.0, 30.0, 10.0, font_id, "AB"))
  let report = verify_ofd(pack(doc))
  let mut detail = ""
  let mut seen = false
  for check in report.failures() {
    if check.name == "every drawn character is embedded" {
      seen = true
      detail = check.detail
    }
  }
  assert_true(seen)
  assert_true(detail.contains("1 of 2"))
  assert_true(detail.contains("B"))
}

///|
test "coverage check passes when the subset has every character" {
  let doc = Document::new()
  let font_id = doc.add_embedded_font("Synth", synthetic_font([0x41, 0x42]))
  let page = doc.add_page()
  ignore(page.text_with_font(20.0, 30.0, 10.0, font_id, "ABBA"))
  let report = verify_ofd(pack(doc))
  let mut detail = ""
  for check in report.checks {
    if check.name == "every drawn character is embedded" {
      detail = check.detail
    }
  }
  assert_true(detail.contains("4 character(s) covered"))
}
