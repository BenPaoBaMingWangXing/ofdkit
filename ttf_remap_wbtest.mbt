///|
/// White-box tests for the cmap builders. Format selection matters: format 4 is
/// universally understood but cannot address code points past U+FFFF, so the
/// writer must only fall back to format 12 when the document needs it.

///|
test "format 4 subtable covers bmp code points" {
  let pairs : Array[(Int32, Int32)] = [(0x41, 1), (0x42, 2), (0x4E2D, 3)]
  let (subtable, _) = build_cmap4(pairs)
  assert_eq(be_u16(subtable, 0), 4)
  // Two segments: the run A,B then 中, plus the mandatory terminator.
  assert_eq(be_u16(subtable, 6), 3 * 2)
}

///|
test "format 12 subtable holds astral code points" {
  let pairs : Array[(Int32, Int32)] = [(0x41, 1), (0x1F600, 2), (0x1F601, 3)]
  let subtable = build_cmap12(pairs)
  assert_eq(be_u16(subtable, 0), 12)
  // Two groups (A alone, then the consecutive emoji pair) of 12 bytes each.
  assert_eq(subtable.length(), 16 + 2 * 12)
  assert_eq(be_u32(subtable, 12), 2)
  // First group start/end/glyph.
  assert_eq(be_u32(subtable, 16), 0x41)
  assert_eq(be_u32(subtable, 24), 1)
}

///|
test "cmap wrapper picks encoding 1 for bmp and 10 for astral" {
  let pairs4 : Array[(Int32, Int32)] = [(0x41, 1)]
  let (sub4, _) = build_cmap4(pairs4)
  let cmap4 = wrap_cmap(sub4)
  assert_eq(be_u16(cmap4, 4), 3) // platform: Windows
  assert_eq(be_u16(cmap4, 6), 1) // encoding: Unicode BMP

  let pairs12 : Array[(Int32, Int32)] = [(0x1F600, 1)]
  let cmap12 = wrap_cmap(build_cmap12(pairs12))
  assert_eq(be_u16(cmap12, 4), 3)
  assert_eq(be_u16(cmap12, 6), 10) // encoding: Unicode full repertoire
}

///|
test "remap assigns new ids in ascending old order and keeps zero" {
  let (ordered, old_to_new) = build_remap(100, [5, 0, 7])
  // Gallery 0 first, then the kept ids in ascending order.
  assert_eq(ordered.length(), 3)
  assert_eq(ordered[0], 0)
  assert_eq(ordered[1], 5)
  assert_eq(ordered[2], 7)
  assert_eq(old_to_new[0], 0)
  assert_eq(old_to_new[5], 1)
  assert_eq(old_to_new[7], 2)
  assert_eq(old_to_new[9], -1)
}
