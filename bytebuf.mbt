///|
/// A growable byte buffer used to assemble ZIP structures and file payloads.
///
/// `Bytes` is immutable in MoonBit, so the backing store is a `FixedArray[Byte]`
/// converted once at the end. Everything here writes little-endian, which is
/// what the ZIP container requires.

///|
pub struct ByteBuf {
  mut data : FixedArray[Byte]
  mut len : Int32
}

///|
pub fn ByteBuf::new() -> ByteBuf {
  { data: FixedArray::make(256, b'\x00'), len: 0, }
}

///|
pub fn ByteBuf::with_capacity(capacity : Int32) -> ByteBuf {
  { data: FixedArray::make(capacity, b'\x00'), len: 0, }
}

///|
pub fn ByteBuf::length(self : ByteBuf) -> Int32 {
  self.len
}

///|
fn ByteBuf::grow(self : ByteBuf, need : Int32) -> Unit {
  let required = self.len + need
  if required <= self.data.length() {
    return
  }
  let mut capacity = self.data.length()
  if capacity == 0 {
    capacity = 64
  }
  while capacity < required {
    capacity = capacity * 2
  }
  let next = FixedArray::make(capacity, b'\x00')
  for i in 0..<self.len {
    next[i] = self.data[i]
  }
  self.data = next
}

///|
pub fn ByteBuf::write_byte(self : ByteBuf, value : Byte) -> Unit {
  self.grow(1)
  self.data[self.len] = value
  self.len = self.len + 1
}

///|
pub fn ByteBuf::write_u16_le(self : ByteBuf, value : UInt32) -> Unit {
  self.write_byte((value & 0xFFU).to_byte())
  self.write_byte(((value >> 8) & 0xFFU).to_byte())
}

///|
pub fn ByteBuf::write_u32_le(self : ByteBuf, value : UInt32) -> Unit {
  self.write_byte((value & 0xFFU).to_byte())
  self.write_byte(((value >> 8) & 0xFFU).to_byte())
  self.write_byte(((value >> 16) & 0xFFU).to_byte())
  self.write_byte(((value >> 24) & 0xFFU).to_byte())
}

///|
/// Big-endian writers. TrueType, unlike ZIP, is big-endian throughout.
pub fn ByteBuf::write_u16_be(self : ByteBuf, value : UInt32) -> Unit {
  self.write_byte(((value >> 8) & 0xFFU).to_byte())
  self.write_byte((value & 0xFFU).to_byte())
}

///|
pub fn ByteBuf::write_u32_be(self : ByteBuf, value : UInt32) -> Unit {
  self.write_byte(((value >> 24) & 0xFFU).to_byte())
  self.write_byte(((value >> 16) & 0xFFU).to_byte())
  self.write_byte(((value >> 8) & 0xFFU).to_byte())
  self.write_byte((value & 0xFFU).to_byte())
}

///|
pub fn ByteBuf::write_bytes(self : ByteBuf, value : Bytes) -> Unit {
  let n = value.length()
  self.grow(n)
  for i in 0..<n {
    self.data[self.len + i] = value[i]
  }
  self.len = self.len + n
}

///|
pub fn ByteBuf::write_ascii(self : ByteBuf, value : String) -> Unit {
  self.write_bytes(@utf8.encode(value))
}

///|
pub fn ByteBuf::to_bytes(self : ByteBuf) -> Bytes {
  Bytes::from_array(self.data[:self.len])
}
