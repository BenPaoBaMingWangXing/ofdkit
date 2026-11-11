///|
/// Tests for the document outline. Readers render it as a bookmark tree, so the
/// only thing that matters is that every destination names a real page.

///|
test "outline entries are counted" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  doc.add_outline("第一章", page, 1)
  doc.add_outline("第二章", page, 1)
  assert_eq(doc.outline_count(), 2)
}

///|
test "outline is serialised with a goto action" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  doc.add_outline("封面", page, 1)
  let xml = @ofdkit.serialize_document(doc)
  assert_true(xml.contains("<ofd:Outlines>"))
  assert_true(xml.contains("Title=\"封面\""))
  assert_true(xml.contains("<ofd:Action Type=\"Goto\">"))
  assert_true(xml.contains("<ofd:Dest>\{page.id}</ofd:Dest>"))
}

///|
test "a document without outlines omits the element" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  let xml = @ofdkit.serialize_document(doc)
  assert_false(xml.contains("ofd:Outlines"))
}

///|
test "outline level below one is clamped to one" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  doc.add_outline("坏层级", page, 0)
  let xml = @ofdkit.serialize_document(doc)
  assert_true(xml.contains("Level=\"1\""))
}

///|
test "a document with an outline verifies" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  doc.add_outline("第一章", page, 1)
  let report = @ofdkit.verify_ofd(doc.to_bytes())
  assert_true(report.passed())
  let mut found = false
  for check in report.checks {
    if check.name == "outline destinations resolve" {
      found = true
      assert_true(check.passed)
    }
  }
  assert_true(found)
}

///|
test "an outline pointing at a missing page fails verification" {
  // Hand-build a document whose outline destination has no matching page.
  let zw = @ofdkit.ZipWriter::new()
  let ofd_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:OFD xmlns:ofd=\"http://www.ofdspec.org/2016\" DocType=\"OFD\" Version=\"1.1\"><ofd:DocBody><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>"
  let doc_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Document xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:CommonData><ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea><ofd:MaxUnitID>5</ofd:MaxUnitID></ofd:CommonData><ofd:Pages><ofd:Page ID=\"1\" BaseLoc=\"Pages/Page_0/Content.xml\"/></ofd:Pages><ofd:Outlines><ofd:Outline ID=\"2\" Title=\"坏链接\" Level=\"1\"><ofd:Actions><ofd:Action Type=\"Goto\"><ofd:Dest>99</ofd:Dest></ofd:Action></ofd:Actions></ofd:Outline></ofd:Outlines></ofd:Document>"
  let page_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ofd:Page xmlns:ofd=\"http://www.ofdspec.org/2016\"><ofd:Content><ofd:Layer ID=\"3\"/></ofd:Content></ofd:Page>"
  zw.add_file("OFD.xml", @utf8.encode(ofd_xml))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(doc_xml))
  zw.add_file("Doc_0/Pages/Page_0/Content.xml", @utf8.encode(page_xml))
  let report = @ofdkit.verify_ofd(zw.finish())
  assert_false(report.passed())
  let mut found = false
  for failure in report.failures() {
    if failure.name == "outline destinations resolve" {
      found = true
    }
  }
  assert_true(found)
}
