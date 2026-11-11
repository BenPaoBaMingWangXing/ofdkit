///|
/// CRC-32 (IEEE 802.3), the checksum used by the ZIP container.
///
/// OFD files are ZIP archives, so every entry needs a CRC-32 of its
/// uncompressed bytes. The table is built once and shared.

///|
let crc32_table : Array[UInt] = make_crc32_table()

///|
fn make_crc32_table() -> Array[UInt] {
  let table : Array[UInt] = Array::make(256, 0U)
  for i in 0..<256 {
    let mut c = i.reinterpret_as_uint()
    for _ in 0..<8 {
      if (c & 1U) != 0U {
        c = 0xEDB88320U ^ (c >> 1)
      } else {
        c = c >> 1
      }
    }
    table[i] = c
  }
  table
}

///|
/// Incremental CRC-32 state. Call `update` for each chunk, then `finalize`.
pub struct Crc32 {
  mut value : UInt
}

///|
pub fn Crc32::new() -> Crc32 {
  { value: 0xFFFFFFFFU }
}

///|
pub fn Crc32::update(self : Crc32, data : Bytes) -> Unit {
  let mut c = self.value
  let n = data.length()
  for i in 0..<n {
    let idx = ((c ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()
    c = crc32_table[idx] ^ (c >> 8)
  }
  self.value = c
}

///|
pub fn Crc32::finalize(self : Crc32) -> UInt {
  self.value ^ 0xFFFFFFFFU
}

///|
pub fn crc32(data : Bytes) -> UInt {
  let c = Crc32::new()
  c.update(data)
  c.finalize()
}
