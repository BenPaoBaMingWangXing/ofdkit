///|
/// Layout helpers: horizontal alignment and tables.
///
/// Everything here is built on `measure_text`, so once a font is embedded the
/// boxes and rules land on real glyph widths rather than guesses.

///|
/// Horizontal alignment of a text run inside its box. `Justify` spreads the
/// slack over the gaps: at spaces when the line has any, otherwise between every
/// pair of characters, which is what Chinese text expects.
pub(all) enum Align {
  Left
  Center
  Right
  Justify
}

///|
/// Draw `text` inside a box of `width` millimetres starting at `x`, aligned
/// according to `align`. The box is not clipped; oversize text simply spills.
pub fn Page::text_aligned(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  size : Double,
  align : Align,
  text : String,
) -> Unit {
  match align {
    Justify => self.text_justified(x, y, width, size, text)
    _ => {
      let measured = self.measure_text(text, size)
      let offset = match align {
        Left => 0.0
        Center => (width - measured) / 2.0
        Right => width - measured
        Justify => 0.0
      }
      self.text(x + offset, y, size, text)
    }
  }
}

///|
/// Whether the gap between two adjacent characters may absorb justification
/// slack. Spaces always may; a pair of ASCII characters inside a word may not,
/// so justifying mixed Chinese/Latin text never pulls "Content.xml" apart.
fn gap_is_stretchable(left : Char, right : Char) -> Bool {
  if left == ' ' || right == ' ' {
    true
  } else {
    !(left.is_ascii() && right.is_ascii())
  }
}

///|
/// Draw `text` stretched to exactly `width` millimetres by widening the gaps
/// between characters: everywhere for Chinese text, at spaces for Latin text.
/// A line that already overflows is drawn unchanged rather than squeezed, so
/// justification never makes text unreadable.
pub fn Page::text_justified(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  size : Double,
  text : String,
) -> Unit {
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let count = chars.length()
  if count < 2 {
    self.text(x, y, size, text)
    return
  }
  let natural = self.measure_text(text, size)
  let slack = width - natural
  if slack <= 0.01 {
    self.text(x, y, size, text)
    return
  }
  let mut gaps = 0
  for i in 0..<(count - 1) {
    if gap_is_stretchable(chars[i], chars[i + 1]) {
      gaps = gaps + 1
    }
  }
  if gaps == 0 {
    self.text(x, y, size, text)
    return
  }
  let extra = slack / gaps.to_double()
  let offsets : Array[Double] = []
  let mut cursor = 0.0
  for i in 0..<count {
    offsets.push(cursor)
    cursor = cursor + self.char_width(chars[i], size)
    if i < count - 1 && gap_is_stretchable(chars[i], chars[i + 1]) {
      cursor = cursor + extra
    }
  }
  ignore(self.text_at_offsets(x, y, size, text, offsets))
}

///|
/// Geometry and styling for `Page::table`.
pub struct TableStyle {
  /// Left edge of the table.
  x : Double
  /// Top edge of the table.
  y : Double
  /// Width of each column, in millimetres. The row count is derived from it.
  column_widths : Array[Double]
  /// Height of each body row.
  row_height : Double
  /// Font size for cell text.
  font_size : Double
  /// Rule width for the grid.
  line_width : Double
  /// Inner padding on the left of a cell.
  padding : Double
  /// When true the first row is drawn with a filled background.
  header : Bool
  /// Header fill colour (only used when `header` is true).
  header_fill : Color
  /// Colour of the grid rules.
  border_color : Color
  /// Fill applied to every second body row, for readability. `None` disables it.
  zebra_fill : Color?
  /// Vertical offset of the text baseline inside a row.
  text_offset : Double
}

///|
/// A sensible default table: 5 mm rows, 4.5 pt text, hairline rules.
pub fn TableStyle::new(
  x : Double,
  y : Double,
  column_widths : Array[Double],
) -> TableStyle {
  {
    x,
    y,
    column_widths,
    row_height: 6.5,
    font_size: 4.2,
    line_width: 0.2,
    padding: 1.5,
    header: true,
    header_fill: Color::new(235, 238, 245),
    border_color: Color::new(150, 155, 165),
    zebra_fill: None,
    text_offset: 4.75,
  }
}

///|
pub fn TableStyle::with_row_height(
  self : TableStyle,
  height : Double,
) -> TableStyle {
  { ..self, row_height: height, }
}

///|
pub fn TableStyle::with_font_size(
  self : TableStyle,
  size : Double,
) -> TableStyle {
  { ..self, font_size: size, }
}

///|
pub fn TableStyle::without_header(self : TableStyle) -> TableStyle {
  { ..self, header: false, }
}

///|
pub fn TableStyle::with_header_fill(
  self : TableStyle,
  color : Color,
) -> TableStyle {
  { ..self, header_fill: color, }
}

///|
pub fn TableStyle::with_border_color(
  self : TableStyle,
  color : Color,
) -> TableStyle {
  { ..self, border_color: color, }
}

///|
/// Fill every second body row with `color`. Zebra striping is what makes a wide
/// table trackable across columns, so it is a style flag rather than something
/// callers have to draw themselves.
pub fn TableStyle::with_zebra(self : TableStyle, color : Color) -> TableStyle {
  { ..self, zebra_fill: Some(color), }
}

///|
pub fn TableStyle::with_padding(
  self : TableStyle,
  padding : Double,
) -> TableStyle {
  { ..self, padding, }
}

///|
/// Total width of the table.
pub fn TableStyle::width(self : TableStyle) -> Double {
  let mut total = 0.0
  for column in self.column_widths {
    total = total + column
  }
  total
}

///|
/// Draw a grid of text. `rows` is a list of equal-length row arrays; cells past
/// the column count are ignored, missing cells are left blank. Returns the y
/// coordinate just below the table.
///
/// Cell text is drawn on one line and clipped by truncation with an ellipsis
/// when it does not fit — a report cell that silently overlaps its neighbour is
/// worse than one that admits it was cut.
pub fn Page::table(
  self : Page,
  style : TableStyle,
  rows : Array[Array[String]],
) -> Double {
  let total_width = style.width()
  let total_height = style.row_height * rows.length().to_double()
  if rows.length() == 0 {
    return style.y
  }
  // Header fill first, so the rules sit on top of it.
  if style.header && rows.length() > 0 {
    self.fill_rect(
      style.x,
      style.y,
      total_width,
      style.row_height,
      style.header_fill,
    )
  }
  // Zebra fills under the rules as well.
  match style.zebra_fill {
    Some(fill) => {
      let mut row = if style.header { 1 } else { 0 }
      while row < rows.length() {
        if row % 2 == 1 {
          self.fill_rect(
            style.x,
            style.y + style.row_height * row.to_double(),
            total_width,
            style.row_height,
            fill,
          )
        }
        row = row + 1
      }
    }
    None => ()
  }
  // Horizontal rules, including the top and bottom edges.
  let mut row_index = 0
  while row_index <= rows.length() {
    let line_y = style.y + style.row_height * row_index.to_double()
    self.line_colored(
      style.x,
      line_y,
      style.x + total_width,
      line_y,
      style.line_width,
      style.border_color,
    )
    row_index = row_index + 1
  }
  // Vertical rules.
  let mut column_x = style.x
  self.line_colored(
    style.x,
    style.y,
    style.x,
    style.y + total_height,
    style.line_width,
    style.border_color,
  )
  for column in style.column_widths {
    column_x = column_x + column
    self.line_colored(
      column_x,
      style.y,
      column_x,
      style.y + total_height,
      style.line_width,
      style.border_color,
    )
  }
  // Cell text.
  for row_index, row in rows {
    let baseline = style.y +
      style.row_height * row_index.to_double() +
      style.text_offset
    for column_index, cell in row {
      if column_index >= style.column_widths.length() {
        continue
      }
      let mut cell_x = style.x
      for i in 0..<column_index {
        cell_x = cell_x + style.column_widths[i]
      }
      let available = style.column_widths[column_index] - style.padding * 2.0
      let fitted = self.fit_text(cell, available, style.font_size)
      self.text(cell_x + style.padding, baseline, style.font_size, fitted)
    }
  }
  style.y + total_height
}

///|
/// Like `paragraph`, but every line is aligned inside `width`. With
/// `Align::Justify` the last line stays left-aligned, which is the convention in
/// typeset prose.
pub fn Page::paragraph_aligned(
  self : Page,
  x : Double,
  y : Double,
  width : Double,
  size : Double,
  line_height : Double,
  align : Align,
  text : String,
) -> Double {
  let lines = self.wrap_text(text, width, size)
  let last = lines.length() - 1
  let mut cursor = y
  for i in 0..<lines.length() {
    let line = lines[i]
    match align {
      Justify =>
        if i == last {
          self.text(x, cursor, size, line)
        } else {
          self.text_justified(x, cursor, width, size, line)
        }
      _ => self.text_aligned(x, cursor, width, size, align, line)
    }
    cursor = cursor + line_height
  }
  cursor
}

///|
/// Shorten `text` so it fits `width`, appending an ellipsis when characters had
/// to be dropped.
pub fn Page::fit_text(
  self : Page,
  text : String,
  width : Double,
  size : Double,
) -> String {
  if self.measure_text(text, size) <= width {
    return text
  }
  let ellipsis = "…"
  let ellipsis_width = self.measure_text(ellipsis, size)
  let limit = width - ellipsis_width
  let out = StringBuilder()
  let mut used = 0.0
  for ch in text {
    let advance = self.char_width(ch, size)
    if used + advance > limit {
      break
    }
    out.write_char(ch)
    used = used + advance
  }
  out.write_stringview(ellipsis)
  out.to_string()
}

///|
/// Top margin used when a table spills onto a new page.
pub const TABLE_PAGE_TOP : Double = 20.0

///|
/// Bottom margin a table must leave free on a page.
pub const TABLE_PAGE_BOTTOM : Double = 20.0

///|
/// Draw `rows` starting at `(style.x, style.y)` on `page`, adding pages as
/// needed. The header row is repeated at the top of every continuation page,
/// which is what makes a long table readable.
///
/// Returns the page the table ended on and the y coordinate below its last row.
pub fn Document::table_across_pages(
  self : Document,
  page : Page,
  style : TableStyle,
  rows : Array[Array[String]],
) -> (Page, Double) {
  if rows.length() == 0 {
    return (page, style.y)
  }
  let has_header = style.header
  let header_rows = if has_header { 1 } else { 0 }
  let body_start = header_rows
  let mut current = page
  let mut cursor = style.y
  let mut index = body_start
  while index < rows.length() {
    // Every page carries the header, so body capacity is one row less.
    let available = current.height - TABLE_PAGE_BOTTOM - cursor
    let capacity = (available / style.row_height).to_int()
    let usable = if has_header { capacity - 1 } else { capacity }
    if usable < 1 {
      // Not even one body row fits; continue on a fresh page.
      current = self.add_page_sized(current.width, current.height)
      cursor = TABLE_PAGE_TOP
      continue
    }
    let remaining = rows.length() - index
    let take = if usable > remaining { remaining } else { usable }
    let block : Array[Array[String]] = []
    if has_header {
      block.push(rows[0])
    }
    for i in 0..<take {
      block.push(rows[index + i])
    }
    let block_style = { ..style, y: cursor, }
    cursor = current.table(block_style, block)
    index = index + take
    if index < rows.length() {
      current = self.add_page_sized(current.width, current.height)
      cursor = TABLE_PAGE_TOP
    }
  }
  (current, cursor)
}
