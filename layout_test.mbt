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
