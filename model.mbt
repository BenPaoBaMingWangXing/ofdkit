///|
/// OFD document model (GB/T 33190-2016).
///
/// All geometry is in millimetres with the origin at the top-left corner of the
/// page, Y growing downwards — exactly what the standard uses. Keeping one unit
/// across the whole API means callers never convert.

///|
/// Device RGB colour, components in 0..255.
pub struct Color {
  r : Int32
  g : Int32
  b : Int32
}

///|
pub fn Color::new(r : Int32, g : Int32, b : Int32) -> Color {
  { r, g, b, }
}

///|
pub fn Color::black() -> Color {
  { r: 0, g: 0, b: 0, }
}

///|
pub fn Color::white() -> Color {
  { r: 255, g: 255, b: 255, }
}

///|
fn Color::to_value_string(self : Color) -> String {
  let r = if self.r < 0 { 0 } else if self.r > 255 { 255 } else { self.r }
  let g = if self.g < 0 { 0 } else if self.g > 255 { 255 } else { self.g }
  let b = if self.b < 0 { 0 } else if self.b > 255 { 255 } else { self.b }
  "\{r} \{g} \{b}"
}

///|
/// An axis-aligned rectangle in millimetres.
pub struct Rect {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
pub fn Rect::new(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Rect {
  { x, y, width, height, }
}

///|
/// A font resource declared in `PublicRes.xml`.
pub struct Font {
  id : Int32
  name : String
  family : String
  /// Embedded TrueType bytes, or empty when the font is left to the reader.
  data : Bytes
}

///|
pub fn Font::named(id : Int32, name : String) -> Font {
  { id, name, family: name, data: Bytes::new(0), }
}

///|
pub fn Font::embedded(id : Int32, name : String, data : Bytes) -> Font {
  { id, name, family: name, data, }
}

///|
pub struct TextObject {
  id : Int32
  boundary : Rect
  font_id : Int32
  size : Double
  color : Color
  text : String
  /// Baseline origin, relative to the bottom-left corner of `boundary`.
  offset_x : Double
  offset_y : Double
  /// Per-character X offsets, relative to `offset_x`. Empty means "draw the run
  /// as one `TextCode`"; one entry per character means "place each glyph
  /// explicitly", which is how letter spacing and justification are expressed.
  glyph_offsets : Array[Double]
}

///|
pub struct PathObject {
  id : Int32
  boundary : Rect
  line_width : Double
  stroke : Bool
  fill : Bool
  stroke_color : Color
  fill_color : Color
  /// OFD abbreviated path data, coordinates relative to `boundary`.
  data : String
}

///|
/// Raster formats OFD can reference directly. The bytes are stored as-is; OFD
/// readers decode PNG and JPEG themselves.
pub enum ImageFormat {
  Png
  Jpeg
}

///|
/// An image registered on the document and stored under `Doc_0/Res`.
pub struct ImageResource {
  id : Int32
  format : ImageFormat
  data : Bytes
}

///|
/// One entry in the document outline, which readers show as a bookmark tree.
pub struct Outline {
  id : Int32
  title : String
  /// Page this entry jumps to.
  page_id : Int32
  /// Nesting depth, 1 being the top level.
  level : Int32
}

///|
/// Object placed on a page that paints a registered image.
pub struct ImageObject {
  id : Int32
  boundary : Rect
  resource_id : Int32
}

///|
pub enum DrawObject {
  Text(TextObject)
  Path(PathObject)
  Image(ImageObject)
}

///|
pub struct Page {
  id : Int32
  width : Double
  height : Double
  objects : Array[DrawObject]
  /// Ids are handed out in blocks so pages never collide.
  mut next_id : Int32
  /// Font used by `text` when no explicit font is given.
  default_font : Int32
  /// Parsed metrics for the default font, when it is embedded. Drives accurate
  /// text measurement and line breaking; `None` falls back to estimation.
  font_face : TtfFace?
}

///|
pub struct Document {
  mut title : String
  mut author : String
  mut subject : String
  creator : String
  mut keywords : String
  mut doc_id : String
  mut creation_date : String
  pages : Array[Page]
  fonts : Array[Font]
  mut next_id : Int32
  /// Font used by new pages; 0 means "fall back to a named system font".
  mut primary_font : Int32
  images : Array[ImageResource]
  outlines : Array[Outline]
}

///|
pub fn Document::new() -> Document {
  {
    title: "",
    author: "",
    subject: "",
    creator: "ofdkit",
    keywords: "",
    doc_id: "ofdkit-document",
    creation_date: "2026-01-01",
    pages: [],
    fonts: [],
    next_id: 1,
    primary_font: 0,
    images: [],
    outlines: [],
  }
}

///|
pub fn Document::set_title(self : Document, title : String) -> Document {
  self.title = title
  self
}

///|
pub fn Document::set_author(self : Document, author : String) -> Document {
  self.author = author
  self
}

///|
pub fn Document::set_subject(self : Document, subject : String) -> Document {
  self.subject = subject
  self
}

///|
pub fn Document::set_keywords(self : Document, keywords : String) -> Document {
  self.keywords = keywords
  self
}

///|
pub fn Document::set_doc_id(self : Document, doc_id : String) -> Document {
  self.doc_id = doc_id
  self
}

///|
pub fn Document::set_creation_date(self : Document, date : String) -> Document {
  self.creation_date = date
  self
}

///|
/// Allocate a document-unique object id.
pub fn Document::alloc_id(self : Document) -> Int32 {
  let id = self.next_id
  self.next_id = self.next_id + 1
  id
}

///|
/// Register a font and return its resource id. Calling this twice with the same
/// name returns the same id, so repeated text calls do not bloat the resource
/// table.
pub fn Document::add_font(self : Document, name : String) -> Int32 {
  for font in self.fonts {
    if font.name == name {
      return font.id
    }
  }
  let id = self.alloc_id()
  self.fonts.push({ id, name, family: name, data: Bytes::new(0), })
  id
}

///|
/// Register a font together with its TrueType bytes, which will be embedded in
/// the package.
pub fn Document::add_embedded_font(
  self : Document,
  name : String,
  data : Bytes,
) -> Int32 {
  for font in self.fonts {
    if font.name == name {
      return font.id
    }
  }
  let id = self.alloc_id()
  self.fonts.push({ id, name, family: name, data, })
  if self.primary_font == 0 {
    self.primary_font = id
  }
  id
}

///|
/// Parse the primary font so pages can measure text with real glyph metrics.
/// Parsing a face is just a table-directory walk, so this is cheap to repeat.
fn Document::default_face(self : Document) -> TtfFace? {
  if self.primary_font == 0 {
    return None
  }
  for font in self.fonts {
    if font.id == self.primary_font && font.data.length() > 0 {
      match parse_ttf(font.data) {
        Ok(face) => return Some(face)
        Err(_) => return None
      }
    }
  }
  None
}

///|
/// Identify a raster image by its magic bytes. OFD stores the original bytes,
/// so the only thing the writer needs to know is which decoder to ask for.
pub fn detect_image_format(data : Bytes) -> Result[ImageFormat, String] {
  if data.length() >= 8 &&
    data[0] == b'\x89' &&
    data[1] == b'\x50' &&
    data[2] == b'\x4E' &&
    data[3] == b'\x47' {
    return Ok(Png)
  }
  if data.length() >= 3 &&
    data[0] == b'\xFF' &&
    data[1] == b'\xD8' &&
    data[2] == b'\xFF' {
    return Ok(Jpeg)
  }
  Err("unsupported image: expected PNG or JPEG magic bytes")
}

///|
/// Register an image and return the resource id used by `Page::image`.
pub fn Document::add_image(
  self : Document,
  data : Bytes,
) -> Result[Int32, String] {
  let format = match detect_image_format(data) {
    Err(message) => return Err(message)
    Ok(format) => format
  }
  let id = self.alloc_id()
  self.images.push({ id, format, data, })
  Ok(id)
}

///|
/// Append an outline entry that jumps to `page`. `level` starts at 1; a deeper
/// level nests under the previous entry of a shallower level.
pub fn Document::add_outline(
  self : Document,
  title : String,
  page : Page,
  level : Int32,
) -> Unit {
  let id = self.alloc_id()
  self.outlines.push({
    id,
    title,
    page_id: page.id,
    level: if level < 1 {
      1
    } else {
      level
    },
  })
}

///|
/// Number of outline entries.
pub fn Document::outline_count(self : Document) -> Int32 {
  self.outlines.length()
}

///|
/// Font id that new pages will use. Zero means the document has no embedded
/// font, and pages fall back to a named system font.
pub fn Document::primary_font_id(self : Document) -> Int32 {
  self.primary_font
}

///|
/// Append an A4 portrait page: 210 x 297 mm.
pub fn Document::add_page(self : Document) -> Page {
  let id = self.alloc_id()
  let page = {
    id,
    width: 210.0,
    height: 297.0,
    objects: [],
    next_id: id * 1000,
    default_font: if self.primary_font != 0 {
      self.primary_font
    } else {
      self.add_font("SimSun")
    },
    font_face: self.default_face(),
  }
  self.pages.push(page)
  page
}

///|
/// Append a page with an explicit size in millimetres.
pub fn Document::add_page_sized(
  self : Document,
  width : Double,
  height : Double,
) -> Page {
  let id = self.alloc_id()
  let page = {
    id,
    width,
    height,
    objects: [],
    next_id: id * 1000,
    default_font: if self.primary_font != 0 {
      self.primary_font
    } else {
      self.add_font("SimSun")
    },
    font_face: self.default_face(),
  }
  self.pages.push(page)
  page
}

///|
pub fn Document::page_count(self : Document) -> Int32 {
  self.pages.length()
}

///|
fn object_id(obj : DrawObject) -> Int32 {
  match obj {
    Text(t) => t.id
    Path(p) => p.id
    Image(i) => i.id
  }
}

///|
/// Largest object id in the document, which is what `MaxUnitID` must report.
/// Page objects are numbered in blocks, so this is not simply the document
/// counter.
pub fn Document::max_unit_id(self : Document) -> Int32 {
  let mut max = self.next_id
  for page in self.pages {
    for obj in page.objects {
      let id = object_id(obj)
      if id > max {
        max = id
      }
    }
  }
  max
}
