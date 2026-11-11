///|
/// Packaging: turn a `Document` into the bytes of an `.ofd` file.

///|
/// Path of the content stream for page `index`.
pub fn page_content_path(index : Int32) -> String {
  "Doc_0/Pages/Page_\{index}/Content.xml"
}

///|
/// Path of an embedded font inside the package.
pub fn font_file_path(font_id : Int32) -> String {
  "Doc_0/Res/Font_\{font_id}.ttf"
}

///|
/// Every entry the package will contain, in write order. Useful for callers
/// that want to inspect a package before building it.
pub fn Document::entry_names(doc : Document) -> Array[String] {
  let names : Array[String] = ["OFD.xml", "Doc_0/Document.xml"]
  if doc.fonts.length() > 0 {
    names.push("Doc_0/PublicRes.xml")
  }
  for i, _ in doc.pages {
    names.push(page_content_path(i))
  }
  for font in doc.fonts {
    if font.data.length() > 0 {
      names.push(font_file_path(font.id))
    }
  }
  names
}

///|
/// Build the complete OFD package.
pub fn Document::to_bytes(doc : Document) -> Bytes {
  if doc.pages.length() == 0 {
    abort("ofdkit: a document needs at least one page before packaging")
  }
  let zw = ZipWriter::new()
  zw.add_file("OFD.xml", @utf8.encode(serialize_ofd_xml(doc)))
  zw.add_file("Doc_0/Document.xml", @utf8.encode(serialize_document(doc)))
  if doc.fonts.length() > 0 {
    zw.add_file("Doc_0/PublicRes.xml", @utf8.encode(serialize_public_res(doc)))
  }
  for i, page in doc.pages {
    zw.add_file(page_content_path(i), @utf8.encode(serialize_content(page)))
  }
  for font in doc.fonts {
    if font.data.length() > 0 {
      zw.add_file(font_file_path(font.id), font.data)
    }
  }
  zw.finish()
}
