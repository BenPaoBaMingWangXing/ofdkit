///|
/// Tests for the TrueType reader. These use hand-built byte sequences rather
/// than a real font file so they run on every target, including wasm.

///|
fn bytes_from(values : Array[Int32]) -> Bytes {
  let tmp = FixedArray::make(values.length(), b'\x00')
  for i, value in values {
    tmp[i] = value.to_byte()
  }
  Bytes::from_array(tmp[:])
}

///|
/// A minimal but structurally valid sfnt header with one table record.
fn minimal_sfnt() -> Bytes {
  bytes_from([
    // sfntVersion 1.0
    0x00, 0x01, 0x00, 0x00,
    // numTables = 1, searchRange = 16, entrySelector = 0, rangeShift = 0
     0x00, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
    // tag "head"
     0x68, 0x65, 0x61, 0x64,
    // checksum
     0x00, 0x00, 0x00, 0x00,
    // offset 28, length 0
     0x00, 0x00, 0x00, 0x1C, 0x00, 0x00, 0x00, 0x00,
  ])
}

///|
test "parse a minimal sfnt header" {
  match @ofdkit.parse_ttf(minimal_sfnt()) {
    Err(message) => fail("expected a parseable font: \{message}")
    Ok(face) => {
      assert_eq(face.table_count(), 1)
      assert_true(face.table("head") is Some(_))
      assert_true(face.table("cmap") is None)
    }
  }
}

///|
test "reject a file that is too short" {
  match @ofdkit.parse_ttf(b"abc") {
    Err(_) => assert_true(true)
    Ok(_) => fail("three bytes cannot be a font")
  }
}

///|
test "reject a font collection with an actionable message" {
  let collection = bytes_from([
    // "ttcf"
    0x74, 0x74, 0x63, 0x66, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
  ])
  match @ofdkit.parse_ttf(collection) {
    Err(message) => assert_true(message.contains("collection"))
    Ok(_) => fail("a .ttc must not be treated as a single face")
  }
}

///|
test "reject an unsupported sfnt version" {
  let bogus = bytes_from([
    0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ])
  match @ofdkit.parse_ttf(bogus) {
    Err(message) => assert_true(message.contains("sfnt"))
    Ok(_) => fail("version 2.0 is not TrueType")
  }
}

///|
test "code points are collected once each in order" {
  let codes = @ofdkit.code_points_of("中文AB中")
  assert_eq(codes.length(), 4)
  // U+4E2D, U+6587, 'A', 'B'
  assert_eq(codes[0], 0x4E2D)
  assert_eq(codes[1], 0x6587)
  assert_eq(codes[2], 0x41)
  assert_eq(codes[3], 0x42)
}

///|
test "code points of an empty string is empty" {
  assert_eq(@ofdkit.code_points_of("").length(), 0)
}

///|
test "subsetting a font without tables fails cleanly" {
  match @ofdkit.parse_ttf(minimal_sfnt()) {
    Err(message) => fail("fixture should parse: \{message}")
    Ok(face) =>
      match @ofdkit.subset_font(face, [0x41]) {
        Err(message) => assert_true(message.contains("glyphs"))
        Ok(_) => fail("a font without maxp cannot be subset")
      }
  }
}
