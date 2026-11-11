///|
/// TrueType font reading, enough to embed a Chinese font into an OFD package.
///
/// OFD references fonts from `PublicRes.xml` and ships the font file inside the
/// archive. A full CJK font is 10–20 MB, so shipping it whole is not an option;
/// the writer keeps only the glyphs a document actually uses.
///
/// This module parses the tables needed for that: `head`, `maxp`, `hhea`,
/// `cmap`, `loca`, `glyf`. Everything else is copied verbatim.

///|
/// One entry from the font's table directory.
pub struct TtfTable {
  tag : String
  offset : Int32
  length : Int32
}

///|
/// A parsed font face. `data` is the original file, kept so tables can be copied
/// without re-encoding.
pub struct TtfFace {
  data : Bytes
  tables : Array[TtfTable]
}

///|
fn be_u16(data : Bytes, at : Int32) -> Int32 {
  ((data[at].to_uint() << 8) | data[at + 1].to_uint()).reinterpret_as_int()
}

///|
fn be_i16(data : Bytes, at : Int32) -> Int32 {
  let value = be_u16(data, at)
  if value >= 0x8000 {
    value - 0x10000
  } else {
    value
  }
}

///|
fn be_u32(data : Bytes, at : Int32) -> Int32 {
  ((data[at].to_uint() << 24) |
  (data[at + 1].to_uint() << 16) |
  (data[at + 2].to_uint() << 8) |
  data[at + 3].to_uint()).reinterpret_as_int()
}

///|
fn tag_of(data : Bytes, at : Int32) -> String {
  let out = StringBuilder()
  for i in 0..<4 {
    out.write_char(data[at + i].to_char())
  }
  out.to_string()
}

///|
/// Parse the table directory. Returns an error string for formats this reader
/// does not handle (notably `.ttc` collections).
pub fn parse_ttf(data : Bytes) -> Result[TtfFace, String] {
  if data.length() < 12 {
    return Err("font file is too short to be a TrueType font")
  }
  let version = be_u32(data, 0)
  if version == 0x74746366 {
    // "ttcf"
    return Err(
      "TrueType collections (.ttc) are not supported; extract a single face first",
    )
  }
  if version != 0x00010000 && version != 0x74727565 {
    // 0x74727565 == "true"
    return Err(
      "not a TrueType font: unsupported sfnt version 0x\{fmt_hex(version.reinterpret_as_uint())}",
    )
  }
  let num_tables = be_u16(data, 4)
  let tables : Array[TtfTable] = []
  for i in 0..<num_tables {
    let base = 12 + i * 16
    if base + 16 > data.length() {
      return Err("font table directory is truncated")
    }
    tables.push({
      tag: tag_of(data, base),
      offset: be_u32(data, base + 8),
      length: be_u32(data, base + 12),
    })
  }
  Ok({ data, tables, })
}

///|
pub fn TtfFace::table_count(self : TtfFace) -> Int32 {
  self.tables.length()
}

///|
pub fn TtfFace::table(self : TtfFace, tag : String) -> TtfTable? {
  for table in self.tables {
    if table.tag == tag {
      return Some(table)
    }
  }
  None
}

///|
/// Units per em from `head`. The 1000/2048 scale factor for OFD sizes.
pub fn TtfFace::units_per_em(self : TtfFace) -> Int32 {
  match self.table("head") {
    Some(head) => be_u16(self.data, head.offset + 18)
    None => 1000
  }
}

///|
pub fn TtfFace::num_glyphs(self : TtfFace) -> Int32 {
  match self.table("maxp") {
    Some(maxp) => be_u16(self.data, maxp.offset + 4)
    None => 0
  }
}

///|
/// 0 for short `loca` offsets (u16, halved), 1 for long (u32).
pub fn TtfFace::index_to_loc_format(self : TtfFace) -> Int32 {
  match self.table("head") {
    Some(head) => be_i16(self.data, head.offset + 50)
    None => 0
  }
}

///|
pub fn TtfFace::number_of_hmetrics(self : TtfFace) -> Int32 {
  match self.table("hhea") {
    Some(hhea) => be_u16(self.data, hhea.offset + 34)
    None => 0
  }
}

///|
/// Byte range of glyph `id` inside `glyf`, or `None` when the glyph is empty.
pub fn TtfFace::glyph_range(self : TtfFace, id : Int32) -> (Int32, Int32)? {
  let loca = match self.table("loca") {
    Some(table) => table
    None => return None
  }
  let glyf = match self.table("glyf") {
    Some(table) => table
    None => return None
  }
  let long_format = self.index_to_loc_format() == 1
  let start = if long_format {
    be_u32(self.data, loca.offset + id * 4)
  } else {
    be_u16(self.data, loca.offset + id * 2) * 2
  }
  let end = if long_format {
    be_u32(self.data, loca.offset + (id + 1) * 4)
  } else {
    be_u16(self.data, loca.offset + (id + 1) * 2) * 2
  }
  if end <= start {
    return None
  }
  // Offsets are relative to the start of the glyf table.
  Some((glyf.offset + start, end - start))
}

///|
/// Advance width of glyph `id`, in font units.
pub fn TtfFace::advance_width(self : TtfFace, id : Int32) -> Int32 {
  let hmtx = match self.table("hmtx") {
    Some(table) => table
    None => return 0
  }
  let metrics = self.number_of_hmetrics()
  if metrics == 0 {
    return 0
  }
  let index = if id < metrics { id } else { metrics - 1 }
  be_u16(self.data, hmtx.offset + index * 4)
}
