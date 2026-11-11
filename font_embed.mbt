///|
/// Embedding fonts into a document.
///
/// The caller supplies the font file and the text the document will draw; the
/// subset is derived from that text, so the package only carries the glyphs it
/// needs. Nothing here touches the filesystem — the CLI reads the font.

///|
/// Collect the distinct code points of `text`.
pub fn code_points_of(text : String) -> Array[Int32] {
  let codes : Array[Int32] = []
  for ch in text {
    let code = ch.to_uint().reinterpret_as_int()
    if !codes.contains(code) {
      codes.push(code)
    }
  }
  codes
}

///|
/// Subset `font_bytes` down to the characters in `text` and register it as this
/// document's font. Returns the resource id used to reference it.
pub fn Document::embed_font_for_text(
  self : Document,
  name : String,
  font_bytes : Bytes,
  text : String,
) -> Result[Int32, String] {
  let face = match parse_ttf(font_bytes) {
    Err(message) => return Err(message)
    Ok(face) => face
  }
  let subset = match subset_font_renumbered(face, code_points_of(text)) {
    Err(message) => return Err(message)
    Ok(bytes) => bytes
  }
  Ok(self.add_embedded_font(name, subset))
}

///|
/// Number of glyphs a font declares, useful for sanity checks before subsetting.
pub fn font_glyph_count(font_bytes : Bytes) -> Result[Int32, String] {
  match parse_ttf(font_bytes) {
    Err(message) => Err(message)
    Ok(face) => Ok(face.num_glyphs())
  }
}
