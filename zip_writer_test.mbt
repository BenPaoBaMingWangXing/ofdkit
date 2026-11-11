///|
/// Read a little-endian u32 at `offset`, used by structural assertions.
fn peek_u32(data : Bytes, offset : Int) -> UInt {
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
test "zip starts with a local file header signature" {
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("OFD.xml", b"<OFD/>")
  let archive = zw.finish()
  assert_eq(peek_u32(archive, 0), 0x04034B50U)
}

///|
test "zip ends with an end-of-central-directory signature" {
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("a.txt", b"hello")
  let archive = zw.finish()
  let len = archive.length()
  assert_eq(peek_u32(archive, len - 22), 0x06054B50U)
}

///|
test "zip records the entry count" {
  let zw = @ofdkit.ZipWriter::new()
  zw.add_file("OFD.xml", b"<OFD/>")
  zw.add_file("Doc_0/Document.xml", b"<Document/>")
  assert_eq(zw.entry_count(), 2)
  let archive = zw.finish()
  let len = archive.length()
  // Total entries live at EOCD + 10.
  let total = archive[len - 12].to_uint() | (archive[len - 11].to_uint() << 8)
  assert_eq(total, 2U)
}

///|
test "stored entry payload is byte identical" {
  let zw = @ofdkit.ZipWriter::new()
  let payload : Bytes = b"stored payload"
  zw.add_file("x.bin", payload)
  let archive = zw.finish()
  // Local header is 30 bytes plus the 5 byte name for "x.bin".
  let start = 30 + 5
  for i in 0..<payload.length() {
    assert_eq(archive[start + i], payload[i])
  }
}
