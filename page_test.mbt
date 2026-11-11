///|
/// Tests for text measurement and line breaking. Without an embedded font the
/// page falls back to the ASCII/CJK estimate, which is deterministic and makes
/// these assertions stable across machines.

///|
test "cjk text measures one em per character" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // Two full-width characters at 10 mm each.
  assert_eq(page.measure_text("中文", 10.0), 20.0)
}

///|
test "ascii text measures roughly half an em per character" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  assert_eq(page.measure_text("ab", 10.0), 10.0)
}

///|
test "wrap breaks a cjk run at the line width" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // 10 mm wide, 5 mm per glyph -> two glyphs per line.
  let lines = page.wrap_text("中文测试换行", 10.0, 5.0)
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "中文")
  assert_eq(lines[1], "测试")
  assert_eq(lines[2], "换行")
}

///|
test "wrap honours explicit newlines" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let lines = page.wrap_text("第一行\n第二行", 100.0, 5.0)
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], "第一行")
  assert_eq(lines[1], "第二行")
}

///|
test "wrap does not start a line with a space" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  // Width fits exactly two glyphs; the space would be the third character.
  let lines = page.wrap_text("中 文", 10.0, 5.0)
  assert_true(lines.length() >= 2)
  assert_false(lines[1].has_prefix(" "))
}

///|
test "paragraph advances by one line height per line and returns the next y" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let before = page.object_count()
  let next_y = page.paragraph(20.0, 30.0, 10.0, 5.0, 8.0, "中文测试换行")
  // Three lines of text were drawn.
  assert_eq(page.object_count() - before, 3)
  // 30 + 3 * 8
  assert_eq(next_y, 54.0)
}

///|
test "a single short word stays on one line" {
  let doc = @ofdkit.Document::new()
  let page = doc.add_page()
  let lines = page.wrap_text("短", 50.0, 5.0)
  assert_eq(lines.length(), 1)
  assert_eq(lines[0], "短")
}
