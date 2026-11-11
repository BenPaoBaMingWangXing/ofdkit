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
pub enum DrawObject {
  Text(TextObject)
  Path(PathObject)
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
