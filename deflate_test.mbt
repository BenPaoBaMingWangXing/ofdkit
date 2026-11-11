///|
/// Round-trip tests for the DEFLATE writer and the verifier's inflater.

///|
fn sample_text() -> Bytes {
  @utf8.encode(
    "ofdkit deflate round trip. the quick brown fox jumps over the lazy dog. " +
    "the quick brown fox jumps over the lazy dog. " +
    "<ofd:TextObject ID=\"1000\" Boundary=\"20 30 60 6\">月度报表</ofd:TextObject>",
  )
}

///|
test "deflate produces a stream the inflater can read back" {
  let original = sample_text()
  let packed = @ofdkit.deflate_raw(original)
  assert_true(packed.length() < original.length())
  match @ofdkit.inflate_raw(packed) {
    Err(message) => fail("inflate failed: \{message}")
    Ok(restored) =>
      assert_eq(@utf8.decode_lossy(restored), @utf8.decode_lossy(original))
  }
}

///|
test "deflate handles highly repetitive input" {
  let original = @utf8.encode("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let packed = @ofdkit.deflate_raw(original)
  // A run of one repeated byte should collapse to a handful of bytes.
  assert_true(packed.length() < 16)
  match @ofdkit.inflate_raw(packed) {
    Err(message) => fail("inflate failed: \{message}")
    Ok(restored) =>
      assert_eq(@utf8.decode_lossy(restored), @utf8.decode_lossy(original))
  }
}

///|
test "deflate handles input shorter than the minimum match" {
  let original : Bytes = b"ab"
  let packed = @ofdkit.deflate_raw(original)
  match @ofdkit.inflate_raw(packed) {
    Err(message) => fail("inflate failed: \{message}")
    Ok(restored) =>
      assert_eq(@utf8.decode_lossy(restored), @utf8.decode_lossy(original))
  }
}

///|
test "deflate handles binary bytes including zero" {
  let original = bytes_from([0, 0, 0, 255, 128, 7, 0, 0, 255, 255, 0, 1, 2, 3])
  let packed = @ofdkit.deflate_raw(original)
  match @ofdkit.inflate_raw(packed) {
    Err(message) => fail("inflate failed: \{message}")
    Ok(restored) => assert_eq(restored.length(), original.length())
  }
}

///|
test "zip writer compresses a compressible entry" {
  let zw = @ofdkit.ZipWriter::new()
  let payload = sample_text()
  zw.add_file("Doc_0/Pages/Page_0/Content.xml", payload)
  let archive = zw.finish()
  // Compression method lives at offset 8 of the local file header, the two
  // sizes at 18 and 22.
  let compression = archive[8].to_uint() | (archive[9].to_uint() << 8)
  assert_eq(compression, 8U)
  let packed = archive[18].to_uint() |
    (archive[19].to_uint() << 8) |
    (archive[20].to_uint() << 16) |
    (archive[21].to_uint() << 24)
  let original = archive[22].to_uint() |
    (archive[23].to_uint() << 8) |
    (archive[24].to_uint() << 16) |
    (archive[25].to_uint() << 24)
  assert_eq(original, payload.length().reinterpret_as_uint())
  assert_true(packed < original)
  assert_true(packed.reinterpret_as_int() < payload.length())
}

///|
test "zip writer leaves a small entry stored" {
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("t.txt", b"hi")
  let archive = zw.finish()
  let compression = archive[8].to_uint() | (archive[9].to_uint() << 8)
  assert_eq(compression, 0U)
}

///|
test "compressed archive survives the verifier read path" {
  let zw = @ofdkit.ZipWriter::new()
  let payload = sample_text()
  zw.add_file("a.xml", payload)
  zw.add_file("tiny.bin", b"x")
  let archive = zw.finish()
  let parsed = match @ofdkit.parse_zip(archive) {
    Ok(a) => a
    Err(message) => abort(message)
  }
  let restored = match parsed.read("a.xml") {
    Ok(b) => b
    Err(message) => abort(message)
  }
  assert_eq(restored.length(), payload.length())
  for i in 0..<payload.length() {
    assert_eq(restored[i], payload[i])
  }
  match parsed.read("tiny.bin") {
    Ok(b) => assert_eq(b.length(), 1)
    Err(message) => abort(message)
  }
}

///|
test "deflate round trips every byte value" {
  let values : Array[Int32] = []
  for i in 0..<256 {
    values.push(i)
  }
  let doubled : Array[Int32] = []
  // Repeat the block so the matcher has something to find.
  for _ in 0..<4 {
    for value in values {
      doubled.push(value)
    }
  }
  let original = bytes_from(doubled)
  let packed = @ofdkit.deflate_raw(original)
  assert_true(packed.length() < original.length())
  match @ofdkit.inflate_raw(packed) {
    Err(message) => fail("inflate failed: \{message}")
    Ok(restored) => {
      assert_eq(restored.length(), original.length())
      for i in 0..<original.length() {
        assert_eq(restored[i], original[i])
      }
    }
  }
}
