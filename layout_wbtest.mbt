///|
/// Tests for alignment and table layout. Without an embedded font the page uses
/// the deterministic ASCII/CJK estimate, so the expected geometry is exact.

///|
/// Pull the first text object out of a page.
fn first_text(page : Page) -> TextObject {
  for obj in page.objects {
    match obj {
      Text(t) => return t
      _ => ()
    }
  }
  abort("page has no text object")
}

///|
test "left aligned text starts at the box origin" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, Left, "中")
  assert_eq(first_text(page).boundary.x, 20.0)
}

///|
test "centred text is offset by half the slack" {
  let doc = Document::new()
  let page = doc.add_page()
  // One full-width glyph at 10 mm inside a 100 mm box: 45 mm of slack each side.
  page.text_aligned(20.0, 30.0, 100.0, 10.0, Center, "中")
  assert_eq(first_text(page).boundary.x, 65.0)
}

///|
test "right aligned text ends at the box edge" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, Right, "中")
  assert_eq(first_text(page).boundary.x, 110.0)
}

///|
test "table returns the bottom edge" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(10.0, 20.0, [40.0, 60.0])
  let bottom = page.table(style, [["a", "b"], ["c", "d"]])
  // Two rows of 6.5 mm starting at 20 mm.
  assert_eq(bottom, 33.0)
}

///|
test "table draws one rule per boundary and one per column" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(10.0, 20.0, [40.0, 60.0])
  // Three rows, two columns: 4 horizontal rules + 3 vertical rules, plus a
  // header fill and 6 text objects.
  let bottom = page.table(style, [["a", "b"], ["c", "d"], ["e", "f"]])
  assert_eq(bottom, 39.5)
  let mut paths = 0
  let mut texts = 0
  for obj in page.objects {
    match obj {
      Path(_) => paths = paths + 1
      Text(_) => texts = texts + 1
      _ => ()
    }
  }
  // 4 horizontal + 3 vertical rules + 1 header fill rectangle.
  assert_eq(paths, 8)
  assert_eq(texts, 6)
}

///|
test "table with no header skips the fill rectangle" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(10.0, 20.0, [50.0]).without_header()
  ignore(page.table(style, [["a"], ["b"]]))
  let mut paths = 0
  for obj in page.objects {
    match obj {
      Path(_) => paths = paths + 1
      _ => ()
    }
  }
  // 3 horizontal + 2 vertical rules, no fill.
  assert_eq(paths, 5)
}

///|
test "fit text leaves short text alone" {
  let doc = Document::new()
  let page = doc.add_page()
  assert_eq(page.fit_text("短", 100.0, 5.0), "短")
}

///|
test "fit text truncates and appends an ellipsis" {
  let doc = Document::new()
  let page = doc.add_page()
  // 3 glyphs at 5 mm each = 15 mm; a 12 mm budget needs truncation.
  let fitted = page.fit_text("一二三四", 12.0, 5.0)
  assert_true(fitted.has_suffix("…"))
  assert_true(page.measure_text(fitted, 5.0) <= 12.0)
}

///|
test "table honours per column widths" {
  let style = TableStyle::new(0.0, 0.0, [30.0, 20.0, 50.0])
  assert_eq(style.width(), 100.0)
}

///|
test "table style builders keep the rest of the settings" {
  let style = TableStyle::new(0.0, 0.0, [30.0])
    .with_row_height(9.0)
    .with_font_size(3.5)
  assert_eq(style.row_height, 9.0)
  assert_eq(style.font_size, 3.5)
  assert_eq(style.width(), 30.0)
  assert_true(style.header)
}

///|
/// Build a table with a header row plus `n` body rows.
fn long_rows(n : Int32) -> Array[Array[String]] {
  let rows : Array[Array[String]] = [["序号", "内容"]]
  for i in 0..<n {
    rows.push(["行\{i}", "内容\{i}"])
  }
  rows
}

///|
test "a short table stays on one page" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 20.0, [40.0, 100.0])
  ignore(doc.table_across_pages(page, style, long_rows(5)))
  assert_eq(doc.page_count(), 1)
}

///|
test "a long table spills onto more pages" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 20.0, [40.0, 100.0])
  // A4 is 297 mm tall; with 20 mm margins and 6.5 mm rows each page holds 38
  // body rows plus the header, so 45 rows needs two pages.
  ignore(doc.table_across_pages(page, style, long_rows(45)))
  assert_eq(doc.page_count(), 2)
}

///|
test "continuation pages repeat the header row" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 20.0, [40.0, 100.0])
  let (last, _) = doc.table_across_pages(page, style, long_rows(45))
  // The second page must contain the header text again.
  let mut header_on_last_page = false
  for obj in last.objects {
    match obj {
      Text(t) => if t.text == "序号" { header_on_last_page = true }
      _ => ()
    }
  }
  assert_true(header_on_last_page)
}

///|
test "a table that exactly fills a page does not add a blank one" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 20.0, [40.0, 100.0])
  // 38 body rows is exactly one page worth.
  ignore(doc.table_across_pages(page, style, long_rows(38)))
  assert_eq(doc.page_count(), 1)
}

///|
test "an empty table leaves the cursor where it was" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 33.0, [40.0])
  let rows : Array[Array[String]] = []
  let (_, y) = doc.table_across_pages(page, style, rows)
  assert_eq(y, 33.0)
  assert_eq(doc.page_count(), 1)
}

///|
test "wrap backs up to a space instead of splitting an ascii word" {
  let doc = Document::new()
  let page = doc.add_page()
  // At size 10 a latin glyph is 5 mm and a space 3 mm: "hello " is 28 mm, and
  // "world" does not fit in the remaining 2 mm of a 30 mm line.
  let lines = page.wrap_text("hello world", 30.0, 10.0)
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], "hello")
  assert_eq(lines[1], "world")
}

///|
test "wrap still splits a single word wider than the line" {
  let doc = Document::new()
  let page = doc.add_page()
  // "abcdefgh" is 40 mm wide at size 10; a 15 mm line cannot hold it whole, so
  // it must be cut rather than looping forever.
  let lines = page.wrap_text("abcdefgh", 15.0, 10.0)
  assert_true(lines.length() >= 2)
  assert_eq(lines[0], "abc")
}

///|
test "wrap does not leave a leading space after a break" {
  let doc = Document::new()
  let page = doc.add_page()
  let lines = page.wrap_text("中文 英文 mix", 20.0, 5.0)
  for line in lines {
    assert_false(line.has_prefix(" "))
  }
}

///|
test "justified CJK text spreads slack between every pair" {
  let doc = Document::new()
  let page = doc.add_page()
  // Two full-width glyphs at 10 mm: 20 mm natural width inside 100 mm.
  page.text_justified(20.0, 30.0, 100.0, 10.0, "中文")
  let obj = first_text(page)
  assert_eq(obj.glyph_offsets.length(), 2)
  assert_eq(obj.glyph_offsets[0], 0.0)
  // 10 mm advance plus the whole 80 mm of slack.
  assert_eq(obj.glyph_offsets[1], 90.0)
}

///|
test "justified latin text widens the gaps around spaces" {
  let doc = Document::new()
  let page = doc.add_page()
  // "a b" at 10 mm: 5 + 3 + 5 = 13 mm natural, 20 mm of slack in a 33 mm box.
  // Both gaps touch the space, so each takes 10 mm.
  page.text_justified(10.0, 30.0, 33.0, 10.0, "a b")
  let obj = first_text(page)
  assert_eq(obj.glyph_offsets.length(), 3)
  assert_eq(obj.glyph_offsets[1], 15.0)
  assert_eq(obj.glyph_offsets[2], 28.0)
}

///|
test "justification never splits a latin word" {
  let doc = Document::new()
  let page = doc.add_page()
  // "中ab" at 10 mm: 10 + 5 + 5 = 20 mm natural, 20 mm of slack in a 40 mm box.
  page.text_justified(10.0, 30.0, 40.0, 10.0, "中ab")
  let obj = first_text(page)
  // Only the CJK/Latin boundary may absorb slack, so "ab" stays 5 mm apart.
  assert_eq(obj.glyph_offsets[1], 30.0)
  assert_eq(obj.glyph_offsets[2], 35.0)
}

///|
test "justified line that already overflows is left alone" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text_justified(10.0, 30.0, 5.0, 10.0, "中文")
  // No room to stretch, so the run stays a single TextCode.
  assert_eq(first_text(page).glyph_offsets.length(), 0)
}

///|
test "justified alignment routes through text_aligned" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, Justify, "中文")
  assert_eq(first_text(page).glyph_offsets.length(), 2)
}

///|
test "letter spacing offsets each glyph by the requested amount" {
  let doc = Document::new()
  let page = doc.add_page()
  // Three full-width glyphs at 10 mm with 2 mm of tracking.
  page.text_spaced(20.0, 30.0, 10.0, 2.0, "中文字")
  let obj = first_text(page)
  assert_eq(obj.glyph_offsets.length(), 3)
  assert_eq(obj.glyph_offsets[1], 12.0)
  assert_eq(obj.glyph_offsets[2], 24.0)
  // The box has to cover the extended run: 24 + 10 = 34 mm.
  assert_eq(obj.boundary.width, 34.0)
}

///|
test "letter spacing is serialised as one TextCode per glyph" {
  let doc = Document::new()
  let page = doc.add_page()
  page.text_spaced(20.0, 30.0, 10.0, 2.0, "中文")
  let xml = serialize_content(page)
  let mut codes = 0
  let mut index = 0
  while index < xml.length() {
    let rest = xml[index:].to_owned()
    if rest.has_prefix("<ofd:TextCode") {
      codes = codes + 1
      index = index + 13
    } else {
      index = index + 1
    }
  }
  assert_eq(codes, 2)
}

///|
test "zebra fills every second body row" {
  let plain = Document::new().add_page()
  let striped = Document::new().add_page()
  let rows = [["h"], ["a"], ["b"], ["c"], ["d"]]
  let style = TableStyle::new(10.0, 20.0, [50.0])
  ignore(plain.table(style, rows))
  ignore(striped.table(style.with_zebra(Color::new(245, 245, 245)), rows))
  // Header plus rows 1 and 3 take a fill of their own.
  assert_eq(striped.objects.length() - plain.objects.length(), 2)
}

///|
test "table rules use the configured border colour" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(10.0, 20.0, [50.0]).with_border_color(
    Color::new(10, 20, 30),
  )
  ignore(page.table(style, [["a"], ["b"]]))
  // Two rows, one column: 3 horizontal rules + 2 vertical rules. Every one of
  // them has to carry the configured colour — a "some line matched" assertion
  // would pass even if two thirds of the grid stayed black.
  let mut rules = 0
  for obj in page.objects {
    match obj {
      Path(p) =>
        if p.stroke && p.line_width < 1.0 {
          rules = rules + 1
          assert_eq(p.stroke_color.r, 10)
          assert_eq(p.stroke_color.g, 20)
          assert_eq(p.stroke_color.b, 30)
        }
      _ => ()
    }
  }
  assert_eq(rules, 5)
}

///|
/// Y coordinates of the zebra fills on a page, in draw order. The header fill is
/// a different colour, so filtering on it keeps the header out of the sample.
fn zebra_rows(page : Page) -> Array[Double] {
  let ys : Array[Double] = []
  for obj in page.objects {
    match obj {
      Path(p) =>
        if p.fill && !p.stroke && p.fill_color.r == 240 {
          ys.push(p.boundary.y)
        }
      _ => ()
    }
  }
  ys
}

///|
test "zebra parity continues across table blocks" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(10.0, 20.0, [50.0]).with_zebra(
    Color::new(240, 243, 249),
  )
  // First block: header plus one body row. Row 1 is odd, so it is striped.
  ignore(page.table(style, [["h"], ["b1"]]))
  // A continuation block starts at row 2 of the same table: the first body row
  // is now even and must stay white, and the one after it takes the stripe.
  ignore(
    page.table({ ..style, y: 40.0, zebra_offset: 1, }, [["h"], ["b2"], ["b3"]]),
  )
  let ys = zebra_rows(page)
  // b1 at 20 + 6.5, then b3 at 40 + 6.5 * 2. No fill for b2.
  assert_eq(ys.length(), 2)
  assert_eq(ys[0], 26.5)
  assert_eq(ys[1], 53.0)
}

///|
test "zebra stripes stay in phase across a page break" {
  let doc = Document::new()
  let page = doc.add_page()
  let style = TableStyle::new(20.0, 20.0, [40.0, 100.0]).with_zebra(
    Color::new(240, 243, 249),
  )
  let (_, _) = doc.table_across_pages(page, style, long_rows(45))
  // 45 body rows are striped on odd numbers: 23 of them. Splitting the table
  // over two pages must not double a stripe or skip one, so the total has to
  // stay 23 even though each page restarts its own row counter.
  let mut striped = 0
  for p in doc.pages {
    striped = striped + zebra_rows(p).length()
  }
  assert_eq(striped, 23)
}
