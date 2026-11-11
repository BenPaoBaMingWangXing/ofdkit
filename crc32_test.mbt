///|
test "crc32 of the canonical check vector" {
  let data : Bytes = b"123456789"
  // 0xCBF43926 is the check value published for CRC-32/ISO-HDLC.
  assert_eq(@ofdkit.crc32(data), 0xCBF43926U)
}

///|
test "crc32 of empty input is zero" {
  let empty : Bytes = Bytes::new(0)
  assert_eq(@ofdkit.crc32(empty), 0U)
}

///|
test "crc32 is chunk independent" {
  let whole : Bytes = b"the quick brown fox jumps over the lazy dog"
  let head : Bytes = b"the quick brown fox "
  let tail : Bytes = b"jumps over the lazy dog"
  let c = @ofdkit.Crc32::new()
  c.update(head)
  c.update(tail)
  assert_eq(c.finalize(), @ofdkit.crc32(whole))
}

///|
test "crc32 differs when a single bit flips" {
  let a : Bytes = b"OFD"
  let b : Bytes = b"OFE"
  assert_true(@ofdkit.crc32(a) != @ofdkit.crc32(b))
}
