///|
/// Minimal ZIP writer tuned for OFD packages.
///
/// OFD (GB/T 33190-2016) is a ZIP archive whose entry point is `OFD.xml`.
/// Entries are written with DEFLATE when that actually shrinks them and stored
/// otherwise, so tiny XML fragments do not pay the two-byte overhead of an
/// empty compressed block. Both methods are plain ZIP, and the container logic
/// stays dependency free.

///|
struct ZipEntry {
  name : String
  crc : UInt32
  /// Compressed size written to the header.
  size : UInt32
  /// Uncompressed size.
  original_size : UInt32
  /// 0 = stored, 8 = deflate. Named `compression` because `method` is reserved.
  compression : UInt32
  offset : UInt32
  is_dir : Bool
}

///|
pub struct ZipWriter {
  out : ByteBuf
  entries : Array[ZipEntry]
  mut finished : Bool
}

///|
pub fn ZipWriter::new() -> ZipWriter {
  { out: ByteBuf::new(), entries: [], finished: false, }
}

///|
/// MS-DOS timestamp for 1980-01-01 00:00:00, the ZIP epoch.
/// OFD does not care about timestamps, so a fixed value keeps output
/// byte-for-byte reproducible.
const DOS_TIME : UInt32 = 0x0000U

///|
const DOS_DATE : UInt32 = 0x0021U

///|
/// Below this size the two-byte DEFLATE block header is a meaningful fraction of
/// the payload, and a fixed-Huffman block rarely wins on a few dozen bytes.
const COMPRESS_MIN_SIZE : Int32 = 64

///|
/// Append one file. `name` must be an ASCII path relative to the archive root,
/// using forward slashes and no leading slash, e.g. `Doc_0/Document.xml`.
///
/// The payload is compressed with DEFLATE only when the result is strictly
/// smaller than the input; readers see the same bytes either way.
pub fn ZipWriter::add_file(
  self : ZipWriter,
  name : String,
  data : Bytes,
) -> Unit {
  if self.finished {
    abort("ZipWriter: cannot add a file after finish()")
  }
  let crc = crc32(data)
  let original_size = data.length().reinterpret_as_uint()
  let mut payload = data
  let mut compression = 0U
  if data.length() >= COMPRESS_MIN_SIZE {
    let packed = deflate_raw(data)
    if packed.length() < data.length() {
      payload = packed
      compression = 8U
    }
  }
  let size = payload.length().reinterpret_as_uint()
  let offset = self.out.length().reinterpret_as_uint()
  let name_bytes = @utf8.encode(name)
  // Local file header.
  self.out.write_u32_le(0x04034B50U)
  self.out.write_u16_le(20U) // version needed to extract
  self.out.write_u16_le(0U) // general purpose flags
  self.out.write_u16_le(compression) // 0 stored, 8 deflate
  self.out.write_u16_le(DOS_TIME)
  self.out.write_u16_le(DOS_DATE)
  self.out.write_u32_le(crc)
  self.out.write_u32_le(size)
  self.out.write_u32_le(original_size)
  self.out.write_u16_le(name_bytes.length().reinterpret_as_uint())
  self.out.write_u16_le(0U) // extra field length
  self.out.write_bytes(name_bytes)
  self.out.write_bytes(payload)
  self.entries.push({
    name,
    crc,
    size,
    original_size,
    compression,
    offset,
    is_dir: false,
  })
}

///|
/// Append a directory entry. OFD packages carry explicit directory records
/// (`Doc_0/`, `Doc_0/Pages/`, ...); some readers rely on them being present.
pub fn ZipWriter::add_directory(self : ZipWriter, name : String) -> Unit {
  if self.finished {
    abort("ZipWriter: cannot add a directory after finish()")
  }
  let dir_name = if name.has_suffix("/") { name } else { name + "/" }
  let name_bytes = @utf8.encode(dir_name)
  let offset = self.out.length().reinterpret_as_uint()
  self.out.write_u32_le(0x04034B50U)
  self.out.write_u16_le(20U)
  self.out.write_u16_le(0U)
  self.out.write_u16_le(0U)
  self.out.write_u16_le(DOS_TIME)
  self.out.write_u16_le(DOS_DATE)
  self.out.write_u32_le(0U)
  self.out.write_u32_le(0U)
  self.out.write_u32_le(0U)
  self.out.write_u16_le(name_bytes.length().reinterpret_as_uint())
  self.out.write_u16_le(0U)
  self.out.write_bytes(name_bytes)
  self.entries.push({
    name: dir_name,
    crc: 0U,
    size: 0U,
    original_size: 0U,
    compression: 0U,
    offset,
    is_dir: true,
  })
}

///|
/// Number of files added so far.
pub fn ZipWriter::entry_count(self : ZipWriter) -> Int32 {
  self.entries.length()
}

///|
/// Names of the files added so far, in insertion order.
pub fn ZipWriter::names(self : ZipWriter) -> Array[String] {
  self.entries.map(fn(entry) { entry.name })
}

///|
/// Write the central directory and end-of-central-directory record, then
/// return the complete archive.
pub fn ZipWriter::finish(self : ZipWriter) -> Bytes {
  if self.finished {
    abort("ZipWriter: finish() called twice")
  }
  let cd_offset = self.out.length().reinterpret_as_uint()
  for entry in self.entries {
    let name_bytes = @utf8.encode(entry.name)
    self.out.write_u32_le(0x02014B50U)
    self.out.write_u16_le(20U) // version made by
    self.out.write_u16_le(20U) // version needed
    self.out.write_u16_le(0U) // flags
    self.out.write_u16_le(entry.compression)
    self.out.write_u16_le(DOS_TIME)
    self.out.write_u16_le(DOS_DATE)
    self.out.write_u32_le(entry.crc)
    self.out.write_u32_le(entry.size)
    self.out.write_u32_le(entry.original_size)
    self.out.write_u16_le(name_bytes.length().reinterpret_as_uint())
    self.out.write_u16_le(0U) // extra
    self.out.write_u16_le(0U) // comment
    self.out.write_u16_le(0U) // disk number start
    self.out.write_u16_le(0U) // internal attributes
    // MS-DOS directory attribute (0x10) for directory records.
    self.out.write_u32_le(if entry.is_dir { 0x10U } else { 0U })
    self.out.write_u32_le(entry.offset)
    self.out.write_bytes(name_bytes)
  }
  let cd_size = self.out.length().reinterpret_as_uint() - cd_offset
  let count = self.entries.length().reinterpret_as_uint()
  self.out.write_u32_le(0x06054B50U)
  self.out.write_u16_le(0U) // this disk
  self.out.write_u16_le(0U) // disk with central directory
  self.out.write_u16_le(count)
  self.out.write_u16_le(count)
  self.out.write_u32_le(cd_size)
  self.out.write_u32_le(cd_offset)
  self.out.write_u16_le(0U) // comment length
  self.finished = true
  self.out.to_bytes()
}
