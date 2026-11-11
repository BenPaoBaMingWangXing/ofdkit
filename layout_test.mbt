///|
/// Tests for alignment and table layout. Without an embedded font the page uses
/// the deterministic ASCII/CJK estimate, so the expected geometry is exact.

///|
/// Pull the first text object out of a page.
fn first_text(page : @ofdkit.Page) -> @ofdkit.TextObject {
  for obj in page.objects {
    match obj {
      @ofdkit.Text(t) => return t
      _ => ()
    }
  }
  abort("page has no text object")
}

///|
test "left aligned text starts at the box origin" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, @ofdkit.Left, "中")
  assert_eq(first_text(page).boundary.x, 20.0)
}

///|
test "centred text is offset by half the slack" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // One full-width glyph at 10 mm inside a 100 mm box: 45 mm of slack each side.
  page.text_aligned(20.0, 30.0, 100.0, 10.0, @ofdkit.Center, "中")
  assert_eq(first_text(page).boundary.x, 65.0)
}

///|
test "right aligned text ends at the box edge" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, @ofdkit.Right, "中")
  assert_eq(first_text(page).boundary.x, 110.0)
}

///|
test "table returns the bottom edge" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(10.0, 20.0, [40.0, 60.0])
  let bottom = page.table(style, [["a", "b"], ["c", "d"]])
  // Two rows of 6.5 mm starting at 20 mm.
  assert_eq(bottom, 33.0)
}

///|
test "table draws one rule per boundary and one per column" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(10.0, 20.0, [40.0, 60.0])
  // Three rows, two columns: 4 horizontal rules + 3 vertical rules, plus a
  // header fill and 6 text objects.
  let bottom = page.table(style, [["a", "b"], ["c", "d"], ["e", "f"]])
  assert_eq(bottom, 39.5)
  let mut paths = 0
  let mut texts = 0
  for obj in page.objects {
    match obj {
      @ofdkit.Path(_) => paths = paths + 1
      @ofdkit.Text(_) => texts = texts + 1
      _ => ()
    }
  }
  // 4 horizontal + 3 vertical rules + 1 header fill rectangle.
  assert_eq(paths, 8)
  assert_eq(texts, 6)
}

///|
test "table with no header skips the fill rectangle" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(10.0, 20.0, [50.0]).without_header()
  ignore(page.table(style, [["a"], ["b"]]))
  let mut paths = 0
  for obj in page.objects {
    match obj {
      @ofdkit.Path(_) => paths = paths + 1
      _ => ()
    }
  }
  // 3 horizontal + 2 vertical rules, no fill.
  assert_eq(paths, 5)
}

///|
test "fit text leaves short text alone" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  assert_eq(page.fit_text("短", 100.0, 5.0), "短")
}

///|
test "fit text truncates and appends an ellipsis" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // 3 glyphs at 5 mm each = 15 mm; a 12 mm budget needs truncation.
  let fitted = page.fit_text("一二三四", 12.0, 5.0)
  assert_true(fitted.has_suffix("…"))
  assert_true(page.measure_text(fitted, 5.0) <= 12.0)
}

///|
test "table honours per column widths" {
  let style = @ofdkit.TableStyle::new(0.0, 0.0, [30.0, 20.0, 50.0])
  assert_eq(style.width(), 100.0)
}

///|
test "table style builders keep the rest of the settings" {
  let style = @ofdkit.TableStyle::new(0.0, 0.0, [30.0])
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
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(20.0, 20.0, [40.0, 100.0])
  ignore(doc.table_across_pages(page, style, long_rows(5)))
  assert_eq(doc.page_count(), 1)
}

///|
test "a long table spills onto more pages" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(20.0, 20.0, [40.0, 100.0])
  // A4 is 297 mm tall; with 20 mm margins and 6.5 mm rows each page holds 38
  // body rows plus the header, so 45 rows needs two pages.
  ignore(doc.table_across_pages(page, style, long_rows(45)))
  assert_eq(doc.page_count(), 2)
}

///|
test "continuation pages repeat the header row" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(20.0, 20.0, [40.0, 100.0])
  let (last, _) = doc.table_across_pages(page, style, long_rows(45))
  // The second page must contain the header text again.
  let mut header_on_last_page = false
  for obj in last.objects {
    match obj {
      @ofdkit.Text(t) => if t.text == "序号" { header_on_last_page = true }
      _ => ()
    }
  }
  assert_true(header_on_last_page)
}

///|
test "a table that exactly fills a page does not add a blank one" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(20.0, 20.0, [40.0, 100.0])
  // 38 body rows is exactly one page worth.
  ignore(doc.table_across_pages(page, style, long_rows(38)))
  assert_eq(doc.page_count(), 1)
}

///|
test "an empty table leaves the cursor where it was" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(20.0, 33.0, [40.0])
  let rows : Array[Array[String]] = []
  let (_, y) = doc.table_across_pages(page, style, rows)
  assert_eq(y, 33.0)
  assert_eq(doc.page_count(), 1)
}

///|
test "wrap backs up to a space instead of splitting an ascii word" {
  let doc = @ofdkit.Document::new()
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
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // "abcdefgh" is 40 mm wide at size 10; a 15 mm line cannot hold it whole, so
  // it must be cut rather than looping forever.
  let lines = page.wrap_text("abcdefgh", 15.0, 10.0)
  assert_true(lines.length() >= 2)
  assert_eq(lines[0], "abc")
}

///|
test "wrap does not leave a leading space after a break" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let lines = page.wrap_text("中文 英文 mix", 20.0, 5.0)
  for line in lines {
    assert_false(line.has_prefix(" "))
  }
}

///|
test "justified CJK text spreads slack between every pair" {
  let doc = @ofdkit.Document::new()
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
  let doc = @ofdkit.Document::new()
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
  let doc = @ofdkit.Document::new()
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
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text_justified(10.0, 30.0, 5.0, 10.0, "中文")
  // No room to stretch, so the run stays a single TextCode.
  assert_eq(first_text(page).glyph_offsets.length(), 0)
}

///|
test "justified alignment routes through text_aligned" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text_aligned(20.0, 30.0, 100.0, 10.0, @ofdkit.Justify, "中文")
  assert_eq(first_text(page).glyph_offsets.length(), 2)
}

///|
test "letter spacing offsets each glyph by the requested amount" {
  let doc = @ofdkit.Document::new()
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
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  page.text_spaced(20.0, 30.0, 10.0, 2.0, "中文")
  let xml = @ofdkit.serialize_content(page)
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
  let plain = @ofdkit.Document::new().add_page()
  let striped = @ofdkit.Document::new().add_page()
  let rows = [["h"], ["a"], ["b"], ["c"], ["d"]]
  let style = @ofdkit.TableStyle::new(10.0, 20.0, [50.0])
  ignore(plain.table(style, rows))
  ignore(
    striped.table(style.with_zebra(@ofdkit.Color::new(245, 245, 245)), rows),
  )
  // Header plus rows 1 and 3 take a fill of their own.
  assert_eq(striped.object_count() - plain.object_count(), 2)
}

///|
test "table rules use the configured border colour" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let style = @ofdkit.TableStyle::new(10.0, 20.0, [50.0]).with_border_color(
    @ofdkit.Color::new(10, 20, 30),
  )
  ignore(page.table(style, [["a"], ["b"]]))
  let mut checked = false
  for obj in page.objects {
    match obj {
      @ofdkit.Path(p) =>
        if p.stroke && p.line_width < 1.0 {
          assert_eq(p.stroke_color.r, 10)
          assert_eq(p.stroke_color.g, 20)
          assert_eq(p.stroke_color.b, 30)
          checked = true
        }
      _ => ()
    }
  }
  assert_true(checked)
}
