///|
/// Drawing API on a page. Everything takes millimetres and returns the object
/// that was appended, so callers can keep a handle for later tweaks.

///|
fn Page::alloc_id(self : Page) -> Int32 {
  let id = self.next_id
  self.next_id = self.next_id + 1
  id
}

///|
/// Rough advance width. Without font metrics we assume full-width for anything
/// outside ASCII and half-width inside, which is accurate enough to size the
/// bounding box. The renderer does the real layout.
pub fn estimate_text_width(text : String, size : Double) -> Double {
  let mut width = 0.0
  for ch in text {
    if ch.is_ascii() {
      if ch == ' ' {
        width = width + size * 0.3
      } else {
        width = width + size * 0.5
      }
    } else {
      width = width + size
    }
  }
  width
}

///|
/// Draw a single line of text with the page's default font.
pub fn Page::text(
  self : Page,
  x : Double,
  y : Double,
  size : Double,
  text : String,
) -> Unit {
  ignore(self.text_object(x, y, size, text))
}

///|
/// Like `text`, but returns the object so callers can adjust it.
pub fn Page::text_object(
  self : Page,
  x : Double,
  y : Double,
  size : Double,
  text : String,
) -> TextObject {
  self.text_with_font(x, y, size, self.default_font, text)
}

///|
/// Draw a single line of text with an explicit font resource id.
pub fn Page::text_with_font(
  self : Page,
  x : Double,
  y : Double,
  size : Double,
  font_id : Int32,
  text : String,
) -> TextObject {
  let width = estimate_text_width(text, size)
  let height = size * 1.2
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    font_id,
    size,
    color: Color::black(),
    text,
    offset_x: 0.0,
    offset_y: size,
  }
  self.objects.push(Text(obj))
  obj
}

///|
/// Draw a straight line between two points.
pub fn Page::line(
  self : Page,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  line_width : Double,
) -> Unit {
  ignore(self.line_object(x1, y1, x2, y2, line_width))
}

///|
pub fn Page::line_object(
  self : Page,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  line_width : Double,
) -> PathObject {
  let left = if x1 < x2 { x1 } else { x2 }
  let top = if y1 < y2 { y1 } else { y2 }
  let dx = if x1 < x2 { x2 - x1 } else { x1 - x2 }
  let dy = if y1 < y2 { y2 - y1 } else { y1 - y2 }
  let thickness = if line_width > 0.0 { line_width } else { 0.1 }
  let width = if dx > thickness { dx } else { thickness }
  let height = if dy > thickness { dy } else { thickness }
  let obj = {
    id: self.alloc_id(),
    boundary: { x: left, y: top, width, height, },
    line_width: thickness,
    stroke: true,
    fill: false,
    stroke_color: Color::black(),
    fill_color: Color::black(),
    data: "M 0 0 L \{fmt_mm(dx)} \{fmt_mm(dy)}",
  }
  self.objects.push(Path(obj))
  obj
}

///|
/// Draw a rectangle. `stroke` and `fill` are independent, matching OFD's model.
pub fn Page::rect(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  line_width : Double,
) -> Unit {
  ignore(self.rect_object(x, y, width, height, line_width))
}

///|
pub fn Page::rect_object(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  line_width : Double,
) -> PathObject {
  let thickness = if line_width > 0.0 { line_width } else { 0.1 }
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    line_width: thickness,
    stroke: true,
    fill: false,
    stroke_color: Color::black(),
    fill_color: Color::black(),
    data: "M 0 0 L \{fmt_mm(width)} 0 L \{fmt_mm(width)} \{fmt_mm(height)} L 0 \{fmt_mm(height)} B",
  }
  self.objects.push(Path(obj))
  obj
}

///|
/// Draw an axis-aligned rectangle filled with a solid colour and no outline.
pub fn Page::fill_rect(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  color : Color,
) -> Unit {
  ignore(self.fill_rect_object(x, y, width, height, color))
}

///|
pub fn Page::fill_rect_object(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  color : Color,
) -> PathObject {
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    line_width: 0.0,
    stroke: false,
    fill: true,
    stroke_color: color,
    fill_color: color,
    data: "M 0 0 L \{fmt_mm(width)} 0 L \{fmt_mm(width)} \{fmt_mm(height)} L 0 \{fmt_mm(height)} B",
  }
  self.objects.push(Path(obj))
  obj
}

///|
/// Draw an arbitrary path. `data` uses OFD abbreviated syntax (`M`, `L`, `C`,
/// `Q`, `B`) with coordinates relative to `(x, y)`.
pub fn Page::path(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  data : String,
  line_width : Double,
) -> Unit {
  ignore(self.path_object(x, y, width, height, data, line_width))
}

///|
pub fn Page::path_object(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  data : String,
  line_width : Double,
) -> PathObject {
  let thickness = if line_width > 0.0 { line_width } else { 0.1 }
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    line_width: thickness,
    stroke: true,
    fill: false,
    stroke_color: Color::black(),
    fill_color: Color::black(),
    data,
  }
  self.objects.push(Path(obj))
  obj
}

///|
pub fn Page::object_count(self : Page) -> Int32 {
  self.objects.length()
}
