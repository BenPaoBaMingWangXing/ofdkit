///|
/// Tests for image resources. The writer never decodes pixels; it only needs to
/// know which decoder the reader should use, so these tests pin the format
/// sniffing and the package wiring.

///|
/// Smallest byte sequence that passes PNG sniffing (real PNGs also carry IHDR).
fn png_magic_bytes() -> Bytes {
  bytes_from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
}

///|
fn jpeg_magic_bytes() -> Bytes {
  bytes_from([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
}

///|
test "png is recognised by its magic bytes" {
  match @ofdkit.detect_image_format(png_magic_bytes()) {
    Err(message) => fail("expected PNG: \{message}")
    Ok(format) =>
      assert_true(
        match format {
          @ofdkit.Png => true
          @ofdkit.Jpeg => false
        },
      )
  }
}

///|
test "jpeg is recognised by its magic bytes" {
  match @ofdkit.detect_image_format(jpeg_magic_bytes()) {
    Err(message) => fail("expected JPEG: \{message}")
    Ok(format) =>
      assert_true(
        match format {
          @ofdkit.Png => false
          @ofdkit.Jpeg => true
        },
      )
  }
}

///|
test "garbage is rejected" {
  match @ofdkit.detect_image_format(b"GIF89a not supported") {
    Err(_) => assert_true(true)
    Ok(_) => fail("GIF must not be accepted")
  }
}

///|
test "adding an image registers a resource and a package entry" {
  let doc = @ofdkit.Document::new()
  let id = match doc.add_image(png_magic_bytes()) {
    Err(message) => fail("expected the image to register: \{message}")
    Ok(id) => id
  }
  ignore(doc.add_page())
  let names = doc.entry_names()
  let mut has_res = false
  let mut has_image = false
  for name in names {
    if name == "Doc_0/DocumentRes.xml" {
      has_res = true
    }
    if name.contains("Image_") {
      has_image = true
    }
  }
  assert_true(has_res)
  assert_true(has_image)
  // The resource id must be positive and appear in the file name.
  assert_true(id > 0)
}

///|
test "content stream references the image resource" {
  let doc = @ofdkit.Document::new()
  let id = match doc.add_image(png_magic_bytes()) {
    Err(message) => fail("fixture: \{message}")
    Ok(id) => id
  }
  let page = doc.add_page()
  page.image(10.0, 10.0, 40.0, 20.0, id)
  let xml = @ofdkit.serialize_content(page)
  assert_true(xml.contains("<ofd:ImageObject"))
  assert_true(xml.contains("ResourceID=\"\{id}\""))
  // CTM maps the unit square onto the 40x20 mm box.
  assert_true(xml.contains("CTM=\"40 0 0 20 0 0\""))
}

///|
test "document resources declare the subtype and file name" {
  let doc = @ofdkit.Document::new()
  let id = match doc.add_image(jpeg_magic_bytes()) {
    Err(message) => fail("fixture: \{message}")
    Ok(id) => id
  }
  let xml = @ofdkit.serialize_document_res(doc)
  assert_true(xml.contains("Subtype=\"JPEG\""))
  assert_true(xml.contains("Image_\{id}.jpg"))
}

///|
test "a document with an image verifies" {
  let doc = @ofdkit.Document::new()
  let id = match doc.add_image(png_magic_bytes()) {
    Err(message) => fail("fixture: \{message}")
    Ok(id) => id
  }
  let page = doc.add_page()
  page.image(10.0, 10.0, 40.0, 20.0, id)
  let report = @ofdkit.verify_ofd(doc.to_bytes())
  assert_true(report.passed())
}
