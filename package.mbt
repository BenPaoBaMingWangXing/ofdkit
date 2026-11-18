///|
/// Packaging: turn a `Document` into the bytes of an `.ofd` file.

///|
/// Path of the content stream for page `index`.
fn page_content_path(index : Int32) -> String {
  "Doc_0/Pages/Page_\{index}/Content.xml"
}

///|
/// Path of an embedded font inside the package.
fn font_file_path(font_id : Int32) -> String {
  "Doc_0/Res/Font_\{font_id}.ttf"
}

///|
/// File name of an image inside `Doc_0/Res`.
fn image_file_name(id : Int32, format : ImageFormat) -> String {
  let extension = match format {
    Png => "png"
    Jpeg => "jpg"
  }
  "Image_\{id}.\{extension}"
}

///|
/// Path of an image inside the package.
fn image_file_path(id : Int32, format : ImageFormat) -> String {
  "Doc_0/Res/\{image_file_name(id, format)}"
}

///|
/// Build the complete OFD package.
///
/// Returns `Err` instead of panicking when the document cannot be packaged — an
/// empty document is a caller mistake, not a broken invariant, and a library
/// that aborts takes the whole process down with it.
pub fn Document::to_bytes(doc : Document) -> Result[Bytes, String] {
  if doc.pages.length() == 0 {
    return Err("a document needs at least one page before it can be packaged")
  }
  let zw = ZipWriter::new()
  zw.add_file("OFD.xml", @utf8.encode(serialize_ofd_xml(doc)))
  zw.add_directory("Doc_0")
  zw.add_file("Doc_0/Document.xml", @utf8.encode(serialize_document(doc)))
  if doc.fonts.length() > 0 {
    zw.add_file("Doc_0/PublicRes.xml", @utf8.encode(serialize_public_res(doc)))
  }
  if doc.images.length() > 0 {
    zw.add_file(
      "Doc_0/DocumentRes.xml",
      @utf8.encode(serialize_document_res(doc)),
    )
  }
  zw.add_directory("Doc_0/Pages")
  for i, page in doc.pages {
    zw.add_directory("Doc_0/Pages/Page_\{i}")
    zw.add_file(page_content_path(i), @utf8.encode(serialize_content(page)))
  }
  let mut res_dir_written = false
  for font in doc.fonts {
    if font.data.length() > 0 {
      if !res_dir_written {
        zw.add_directory("Doc_0/Res")
        res_dir_written = true
      }
      zw.add_file(font_file_path(font.id), font.data)
    }
  }
  for image in doc.images {
    if !res_dir_written {
      zw.add_directory("Doc_0/Res")
      res_dir_written = true
    }
    zw.add_file(image_file_path(image.id, image.format), image.data)
  }
  Ok(zw.finish())
}
