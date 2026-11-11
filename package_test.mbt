///|
/// Structural tests for the OFD serialisers. They assert on the documents the
/// emitters produce, which is the layer a reader actually parses.

///|
fn contains(haystack : String, needle : String) -> Bool {
  haystack.contains(needle)
}

///|
test "ofd.xml declares the namespace and points at the doc root" {
  let doc = @ofdkit.Document::new().set_title("测试文档")
  let xml = @ofdkit.serialize_ofd_xml(doc)
  assert_true(contains(xml, "http://www.ofdspec.org/2016"))
  assert_true(contains(xml, "<ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot>"))
  assert_true(contains(xml, "<ofd:Title>测试文档</ofd:Title>"))
}

///|
test "document.xml lists every page with a base location" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  ignore(doc.add_page_sized(148.0, 210.0))
  let xml = @ofdkit.serialize_document(doc)
  assert_true(contains(xml, "Pages/Page_0/Content.xml"))
  assert_true(contains(xml, "Pages/Page_1/Content.xml"))
  assert_true(contains(xml, "PublicRes.xml"))
}

///|
test "document.xml carries the A4 physical box" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  let xml = @ofdkit.serialize_document(doc)
  assert_true(contains(xml, "<ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox>"))
}

///|
test "public resources declare a font with charset unicode" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  let xml = @ofdkit.serialize_public_res(doc)
  assert_true(contains(xml, "FontName=\"SimSun\""))
  assert_true(contains(xml, "Charset=\"unicode\""))
}

///|
test "content.xml emits a text object with escaped text" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text(20.0, 30.0, 5.0, "A&B <标签>")
  let xml = @ofdkit.serialize_content(page)
  assert_true(contains(xml, "<ofd:TextObject"))
  assert_true(contains(xml, "A&amp;B &lt;标签&gt;"))
  assert_true(contains(xml, "Size=\"5\""))
}

///|
test "content.xml emits a path object with abbreviated data" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.rect(10.0, 10.0, 50.0, 20.0, 0.3)
  let xml = @ofdkit.serialize_content(page)
  assert_true(contains(xml, "<ofd:PathObject"))
  assert_true(contains(xml, "AbbreviatedData>M 0 0 L 50 0 L 50 20 L 0 20 B<"))
  assert_true(contains(xml, "LineWidth=\"0.3\""))
}

///|
test "package entries are what the standard expects" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  ignore(doc.add_page())
  let names = doc.entry_names()
  assert_eq(names[0], "OFD.xml")
  assert_eq(names[1], "Doc_0/Document.xml")
  assert_eq(names[2], "Doc_0/PublicRes.xml")
  assert_eq(names[3], "Doc_0/Pages/Page_0/Content.xml")
  assert_eq(names[4], "Doc_0/Pages/Page_1/Content.xml")
}

///|
test "packaged document is a zip archive with an ofd entry first" {
  let doc = @ofdkit.Document::new()
  ignore(doc.add_page())
  let bytes = doc.to_bytes()
  // Local file header signature, little endian.
  assert_eq(bytes[0], b'\x50')
  assert_eq(bytes[1], b'\x4b')
  assert_eq(bytes[2], b'\x03')
  assert_eq(bytes[3], b'\x04')
}

///|
test "text width estimate is full width for cjk and half for ascii" {
  assert_eq(@ofdkit.estimate_text_width("中文", 10.0), 20.0)
  assert_eq(@ofdkit.estimate_text_width("ab", 10.0), 10.0)
}
