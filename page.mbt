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
/// Advance width of a single character, in millimetres.
fn Page::char_width(self : Page, ch : Char, size : Double) -> Double {
  match self.font_face {
    None => estimate_text_width(ch.to_string(), size)
    Some(face) => {
      let upem = face.units_per_em()
      if upem <= 0 {
        return estimate_text_width(ch.to_string(), size)
      }
      let glyph = face.glyph_for_char(ch.to_uint().reinterpret_as_int())
      face.advance_width(glyph).to_double() / upem.to_double() * size
    }
  }
}

///|
/// Width of `text` at `size` millimetres. Uses the embedded font's own advance
/// widths when one is present, and falls back to the ASCII/CJK estimate when it
/// is not.
pub fn Page::measure_text(self : Page, text : String, size : Double) -> Double {
  match self.font_face {
    None => estimate_text_width(text, size)
    Some(face) => {
      let upem = face.units_per_em()
      if upem <= 0 {
        return estimate_text_width(text, size)
      }
      let mut units = 0
      for ch in text {
        let glyph = face.glyph_for_char(ch.to_uint().reinterpret_as_int())
        units = units + face.advance_width(glyph)
      }
      units.to_double() / upem.to_double() * size
    }
  }
}

///|
/// Break `text` into lines that fit `width` millimetres. Honours explicit
/// newlines, never starts a line with a space, and does not split an ASCII word
/// unless the word alone is wider than the line.
pub fn Page::wrap_text(
  self : Page,
  text : String,
  width : Double,
  size : Double,
) -> Array[String] {
  // Working in code points makes it easy to move a partial line to the next
  // row when we back up to a space.
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let lines : Array[String] = []
  let mut cursor = 0
  let n = chars.length()
  while cursor < n {
    // A hard newline ends the line immediately.
    if chars[cursor] == '\n' {
      lines.push("")
      cursor = cursor + 1
      continue
    }
    // Measure forward until the line overflows or we hit a newline.
    let chunk : Array[Char] = []
    let mut chunk_width = 0.0
    let mut index = cursor
    while index < n && chars[index] != '\n' {
      let advance = self.char_width(chars[index], size)
      if chunk_width + advance > width && chunk.length() > 0 {
        break
      }
      chunk.push(chars[index])
      chunk_width = chunk_width + advance
      index = index + 1
    }
    if index >= n || chars[index] == '\n' {
      // Everything that is left fits on this line.
      lines.push(string_of_chars(chunk))
      cursor = index
      if cursor < n && chars[cursor] == '\n' {
        cursor = cursor + 1
      }
      continue
    }
    // Overflowed. Back up to the last space so we do not split a word, but only
    // when that space is not at the very start of the line.
    let mut break_at = -1
    let mut i = chunk.length() - 1
    while i > 0 {
      if chunk[i] == ' ' {
        break_at = i
        break
      }
      i = i - 1
    }
    if break_at > 0 {
      let head : Array[Char] = []
      for k in 0..<break_at {
        head.push(chunk[k])
      }
      lines.push(string_of_chars(head))
      cursor = cursor + break_at + 1 // skip the space
    } else {
      lines.push(string_of_chars(chunk))
      cursor = cursor + chunk.length()
    }
  }
  lines
}

///|
/// Join code points into a string.
fn string_of_chars(chars : Array[Char]) -> String {
  let out = StringBuilder()
  for ch in chars {
    out.write_char(ch)
  }
  out.to_string()
}

///|
/// Draw wrapped text starting at `(x, y)`, one line per `line_height`
/// millimetres. Returns the y coordinate below the last line.
pub fn Page::paragraph(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  size : Double,
  line_height : Double,
  text : String,
) -> Double {
  self.paragraph_aligned(x, y, width, size, line_height, Left, text)
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
  let width = self.measure_text(text, size)
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
    glyph_offsets: [],
  }
  self.objects.push(Text(obj))
  obj
}

///|
/// Draw `text` with explicit per-character X offsets, measured from `x`. This is
/// the primitive behind letter spacing and justification: the caller decides
/// where each glyph goes, and each one becomes its own `TextCode`.
pub fn Page::text_at_offsets(
  self : Page,
  x : Double,
  y : Double,
  size : Double,
  text : String,
  offsets : Array[Double],
) -> TextObject {
  // The bounding box has to cover the last glyph, not the sum of the advances,
  // because spacing may push characters past a natural `measure_text`.
  let last = offsets.length() - 1
  let mut last_char : Char = ' '
  let mut seen = 0
  for ch in text {
    if seen == last {
      last_char = ch
    }
    seen = seen + 1
  }
  let mut width = self.measure_text(text, size)
  if last >= 0 {
    let tail = if seen > 0 { self.char_width(last_char, size) } else { 0.0 }
    width = if offsets[last] + tail > width {
      offsets[last] + tail
    } else {
      width
    }
  }
  let height = size * 1.2
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    font_id: self.default_font,
    size,
    color: Color::black(),
    text,
    offset_x: 0.0,
    offset_y: size,
    glyph_offsets: offsets,
  }
  self.objects.push(Text(obj))
  obj
}

///|
/// Draw `text` with `spacing` millimetres inserted after every character.
/// Negative values tighten the run.
pub fn Page::text_spaced(
  self : Page,
  x : Double,
  y : Double,
  size : Double,
  spacing : Double,
  text : String,
) -> Unit {
  let offsets : Array[Double] = []
  let mut cursor = 0.0
  for ch in text {
    offsets.push(cursor)
    cursor = cursor + self.char_width(ch, size) + spacing
  }
  ignore(self.text_at_offsets(x, y, size, text, offsets))
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
  self.line_object_with(x1, y1, x2, y2, line_width, Color::black())
}

///|
/// Draw a straight line in a given colour. Table rules use this so a grid can be
/// grey instead of printer-black.
pub fn Page::line_colored(
  self : Page,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  line_width : Double,
  color : Color,
) -> Unit {
  ignore(self.line_object_with(x1, y1, x2, y2, line_width, color))
}

///|
fn Page::line_object_with(
  self : Page,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  line_width : Double,
  color : Color,
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
    stroke_color: color,
    fill_color: color,
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
/// Paint a registered image into `(x, y, width, height)` millimetres. The image
/// is stretched to fill the box; OFD has no aspect-preserving mode at this
/// level, so compute the box yourself when the ratio matters.
pub fn Page::image(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  resource_id : Int32,
) -> Unit {
  let obj = {
    id: self.alloc_id(),
    boundary: { x, y, width, height, },
    resource_id,
  }
  self.objects.push(Image(obj))
}

///|
pub fn Page::object_count(self : Page) -> Int32 {
  self.objects.length()
}
