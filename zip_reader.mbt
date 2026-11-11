///|
/// Minimal ZIP reader for verification.
///
/// This is deliberately small: it parses the central directory and reads stored
/// or fixed-Huffman-deflated entries, which is exactly the subset `ofdkit`
/// writes. It exists so the project can validate its own output without
/// shelling out to another tool.

///|
pub struct ZipEntryInfo {
  name : String
  compression : UInt32
  crc : UInt32
  compressed_size : Int32
  uncompressed_size : Int32
  local_offset : Int32
}

///|
pub struct ZipArchive {
  entries : Array[ZipEntryInfo]
  data : Bytes
}

///|
fn read_u16(data : Bytes, offset : Int32) -> UInt32 {
  data[offset].to_uint() | (data[offset + 1].to_uint() << 8)
}

///|
fn read_u32(data : Bytes, offset : Int32) -> UInt32 {
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
/// Locate the end-of-central-directory record by scanning backwards.
fn find_eocd(data : Bytes) -> Int32 {
  let len = data.length()
  if len < 22 {
    return -1
  }
  let lowest = if len > 66000 { len - 66000 } else { 0 }
  let mut i = len - 22
  while i >= lowest {
    if read_u32(data, i) == 0x06054B50U {
      return i
    }
    i = i - 1
  }
  -1
}

///|
/// Parse the central directory. Returns an error string when the archive is
/// malformed or uses a feature this reader does not implement.
pub fn parse_zip(data : Bytes) -> Result[ZipArchive, String] {
  let eocd = find_eocd(data)
  if eocd < 0 {
    return Err("not a zip archive: end of central directory not found")
  }
  let count = read_u16(data, eocd + 10).reinterpret_as_int()
  let cd_offset = read_u32(data, eocd + 16).reinterpret_as_int()
  if cd_offset < 0 || cd_offset >= data.length() {
    return Err("corrupt zip: central directory offset out of range")
  }
  let entries : Array[ZipEntryInfo] = []
  let mut cursor = cd_offset
  for _ in 0..<count {
    if cursor + 46 > data.length() {
      return Err("corrupt zip: central directory entry truncated")
    }
    if read_u32(data, cursor) != 0x02014B50U {
      return Err("corrupt zip: bad central directory signature")
    }
    let compression = read_u16(data, cursor + 10)
    let crc = read_u32(data, cursor + 16)
    let compressed_size = read_u32(data, cursor + 20).reinterpret_as_int()
    let uncompressed_size = read_u32(data, cursor + 24).reinterpret_as_int()
    let name_len = read_u16(data, cursor + 28).reinterpret_as_int()
    let extra_len = read_u16(data, cursor + 30).reinterpret_as_int()
    let comment_len = read_u16(data, cursor + 32).reinterpret_as_int()
    let local_offset = read_u32(data, cursor + 42).reinterpret_as_int()
    let name_start = cursor + 46
    let name = utf8_decode_bytes(data, name_start, name_len)
    entries.push({
      name,
      compression,
      crc,
      compressed_size,
      uncompressed_size,
      local_offset,
    })
    cursor = name_start + name_len + extra_len + comment_len
  }
  Ok({ entries, data, })
}

///|
/// Copy a slice of `data` into a fresh `Bytes`.
fn slice_bytes(data : Bytes, start : Int32, length : Int32) -> Bytes {
  let tmp = FixedArray::make(length, b'\x00')
  for i in 0..<length {
    tmp[i] = data[start + i]
  }
  Bytes::from_array(tmp[:])
}

///|
/// Decode a UTF-8 slice into a string. Zip entry names in an OFD package are
/// ASCII paths, so lossy decoding is safe here and avoids a raise site.
fn utf8_decode_bytes(data : Bytes, start : Int32, length : Int32) -> String {
  @utf8.decode_lossy(slice_bytes(data, start, length))
}

///|
pub fn ZipArchive::names(self : ZipArchive) -> Array[String] {
  self.entries.map(fn(entry) { entry.name })
}

///|
pub fn ZipArchive::contains(self : ZipArchive, name : String) -> Bool {
  for entry in self.entries {
    if entry.name == name {
      return true
    }
  }
  false
}

///|
pub fn ZipArchive::entry(self : ZipArchive, name : String) -> ZipEntryInfo? {
  for entry in self.entries {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
/// Read an entry's bytes, transparently inflating DEFLATE entries.
pub fn ZipArchive::read(
  self : ZipArchive,
  name : String,
) -> Result[Bytes, String] {
  match self.entry(name) {
    None => Err("missing entry: \{name}")
    Some(entry) => {
      if entry.compression != 0U && entry.compression != 8U {
        return Err(
          "entry \{name} uses compression method \{entry.compression}; only stored and deflate are readable",
        )
      }
      let header_at = entry.local_offset
      if header_at + 30 > self.data.length() {
        return Err("corrupt zip: header_at header truncated for \{name}")
      }
      if read_u32(self.data, header_at) != 0x04034B50U {
        return Err("corrupt zip: bad header_at header signature for \{name}")
      }
      let name_len = read_u16(self.data, header_at + 26).reinterpret_as_int()
      let extra_len = read_u16(self.data, header_at + 28).reinterpret_as_int()
      let start = header_at + 30 + name_len + extra_len
      let stored = entry.compressed_size
      if start + stored > self.data.length() {
        return Err("corrupt zip: payload out of range for \{name}")
      }
      let raw = slice_bytes(self.data, start, stored)
      let payload = if entry.compression == 0U {
        raw
      } else {
        match inflate_raw(raw) {
          Ok(bytes) => bytes
          Err(message) => return Err("cannot inflate \{name}: \{message}")
        }
      }
      if payload.length() != entry.uncompressed_size {
        return Err(
          "size mismatch for \{name}: header says \{entry.uncompressed_size}, got \{payload.length()}",
        )
      }
      if crc32(payload) != entry.crc {
        return Err("crc mismatch for \{name}")
      }
      Ok(payload)
    }
  }
}
