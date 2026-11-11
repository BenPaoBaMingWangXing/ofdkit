///|
/// Tests for the reader and the structural verifier. These are the checks that
/// back the "可验证" claim in the README: a package we produce must survive a
/// round trip through an independent parser.

///|
test "zip reader round trips a stored entry" {
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("OFD.xml", b"<ofd:OFD/>")
  zw.add_file("Doc_0/Document.xml", b"<ofd:Document/>")
  let archive = zw.finish()
  match @ofdkit.parse_zip(archive) {
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
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("OFD.xml", b"<ofd:OFD/>")
  let archive = zw.finish()
  let keep = archive.length() - 10
  let tmp = FixedArray::make(keep, b'\x00')
  for i in 0..<keep {
    tmp[i] = archive[i]
  }
  let short = Bytes::from_array(tmp[:])
  // Not a valid archive any more; parse must fail rather than panic.
  match @ofdkit.parse_zip(short) {
    Err(_) => assert_true(true)
    Ok(_) => fail("a truncated archive should not parse")
  }
}

///|
test "verify accepts a well formed document" {
  let doc = @ofdkit.Document::new().set_title("示例")
  let page = doc.add_page()
  page.text(20.0, 20.0, 5.0, "你好")
  let report = @ofdkit.verify_ofd(doc.to_bytes())
  assert_true(report.passed())
  assert_eq(report.failures().length(), 0)
}

///|
test "verify reports every check it ran" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  let report = @ofdkit.verify_ofd(doc.to_bytes())
  assert_true(report.checks.length() >= 8)
  assert_true(report.summary().contains("checks passed"))
}

///|
test "verify rejects bytes that are not an archive" {
  let junk : Bytes = b"not an ofd file at all"
  let report = @ofdkit.verify_ofd(junk)
  assert_false(report.passed())
}

///|
test "verify catches a package missing its page stream" {
  // Assemble a package by hand that claims a page but ships no content stream.
  let zw = @ofdkit.ZipWriter::new()
  let ofd_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:OFD xmlns:ofd=\"http://www.ofdspec.org/2016\" DocType=\"OFD\" Version=\"1.1\"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>"
  let doc_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Document xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:Pages><ofd:Page ID=\"1\" BaseLoc=\"Pages/Page_0/Content.xml\"/></ofd:Pages></ofd:Document>"
  zw.add_file("OFD.xml", @utf8.encode(ofd_xml))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(doc_xml))
  let report = @ofdkit.verify_ofd(zw.finish())
  assert_false(report.passed())
  assert_true(report.failures().length() > 0)
}

///|
test "max unit id covers page object ids" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text(10.0, 10.0, 4.0, "a")
  page.text(10.0, 20.0, 4.0, "b")
  let max = doc.max_unit_id()
  for obj in page.objects {
    let id = match obj {
      @ofdkit.Text(t) => t.id
      @ofdkit.Path(p) => p.id
    }
    assert_true(max >= id)
  }
}

///|
test "verify rejects a package whose font file is not a font" {
  // Hand-build a package that declares a font and ships garbage bytes for it.
  let zw = @ofdkit.ZipWriter::new()
  let ofd_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:OFD xmlns:ofd=\"http://www.ofdspec.org/2016\" DocType=\"OFD\" Version=\"1.1\"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>"
  let doc_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Document xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:CommonData><ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea><ofd:PublicRes>PublicRes.xml</ofd:PublicRes><ofd:MaxUnitID>4</ofd:MaxUnitID></ofd:CommonData><ofd:Pages><ofd:Page ID=\"1\" BaseLoc=\"Pages/Page_0/Content.xml\"/></ofd:Pages></ofd:Document>"
  let res_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Res xmlns:ofd=\"http://www.ofdspec.org/2016\" BaseLoc=\"Res\"><ofd:Fonts><ofd:Font ID=\"2\" FontName=\"SimHei\" FamilyName=\"SimHei\" Charset=\"unicode\"><ofd:FontFile>Font_2.ttf</ofd:FontFile></ofd:Font></ofd:Fonts></ofd:Res>"
  let page_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Page xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:Content><ofd:Layer ID=\"3\"/></ofd:Content></ofd:Page>"
  zw.add_file("OFD.xml", @utf8.encode(ofd_xml))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(doc_xml))
  zw.add_file("Doc_0/PublicRes.xml", @utf8.encode(res_xml))
  zw.add_file("Doc_0/Pages/Page_0/Content.xml", @utf8.encode(page_xml))
  zw.add_file("Doc_0/Res/Font_2.ttf", b"this is not a font file")
  let report = @ofdkit.verify_ofd(zw.finish())
  assert_false(report.passed())
  let mut found = false
  for failure in report.failures() {
    if failure.name == "embedded fonts are readable" {
      found = true
    }
  }
  assert_true(found)
}
