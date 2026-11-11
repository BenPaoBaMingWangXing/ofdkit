///|
/// `cmap` decoding: mapping Unicode code points to glyph ids.
///
/// Two subtable formats matter in practice: format 4 covers the BMP and is what
/// older CJK fonts ship, format 12 covers the full code space. We pick the best
/// Unicode subtable available and fall back to the Windows BMP one.

///|
/// A selected character map subtable: byte offset of the subtable and its
/// format number.
pub struct CmapSubtable {
  offset : Int32
  format : Int32
}

///|
fn encoding_priority(platform : Int32, encoding : Int32) -> Int32 {
  // Lower is better. Windows UCS-4, then Unicode full repertoire, then BMP.
  if platform == 3 && encoding == 10 {
    return 0
  }
  if platform == 0 && (encoding == 4 || encoding == 6) {
    return 1
  }
  if platform == 0 {
    return 2
  }
  if platform == 3 && encoding == 1 {
    return 3
  }
  -1
}

///|
pub fn TtfFace::cmap(self : TtfFace) -> CmapSubtable? {
  let table = match self.table("cmap") {
    Some(table) => table
    None => return None
  }
  let num = be_u16(self.data, table.offset + 2)
  let mut best : CmapSubtable? = None
  let mut best_rank = 99
  for i in 0..<num {
    let record = table.offset + 4 + i * 8
    let platform = be_u16(self.data, record)
    let encoding = be_u16(self.data, record + 2)
    let sub_offset = table.offset + be_u32(self.data, record + 4)
    let rank = encoding_priority(platform, encoding)
    if rank >= 0 && rank < best_rank {
      let format = be_u16(self.data, sub_offset)
      if format == 4 || format == 12 {
        best = Some({ offset: sub_offset, format, })
        best_rank = rank
      }
    }
  }
  best
}

///|
/// Look up a code point. Returns 0 (`.notdef`) when the font has no glyph for it.
pub fn TtfFace::glyph_for_char(self : TtfFace, code : Int32) -> Int32 {
  match self.cmap() {
    None => 0
    Some(cmap) =>
      if cmap.format == 4 {
        self.glyph_from_format4(cmap.offset, code)
      } else {
        self.glyph_from_format12(cmap.offset, code)
      }
  }
}

///|
fn TtfFace::glyph_from_format4(
  self : TtfFace,
  offset : Int32,
  code : Int32,
) -> Int32 {
  if code > 0xFFFF {
    return 0
  }
  let seg_count = be_u16(self.data, offset + 6) / 2
  let end_codes = offset + 14
  let start_codes = end_codes + seg_count * 2 + 2
  let id_deltas = start_codes + seg_count * 2
  let id_range_offsets = id_deltas + seg_count * 2
  for i in 0..<seg_count {
    let end = be_u16(self.data, end_codes + i * 2)
    if code > end {
      continue
    }
    let start = be_u16(self.data, start_codes + i * 2)
    if code < start {
      return 0
    }
    let delta = be_i16(self.data, id_deltas + i * 2)
    let range_offset = be_u16(self.data, id_range_offsets + i * 2)
    if range_offset == 0 {
      return (code + delta) & 0xFFFF
    }
    let glyph_at = id_range_offsets + i * 2 + range_offset + (code - start) * 2
    let glyph = be_u16(self.data, glyph_at)
    if glyph == 0 {
      return 0
    }
    return (glyph + delta) & 0xFFFF
  }
  0
}

///|
fn TtfFace::glyph_from_format12(
  self : TtfFace,
  offset : Int32,
  code : Int32,
) -> Int32 {
  let groups = be_u32(self.data, offset + 12)
  let base = offset + 16
  for i in 0..<groups {
    let group = base + i * 12
    let start = be_u32(self.data, group)
    if code < start {
      return 0
    }
    let end = be_u32(self.data, group + 4)
    if code <= end {
      let start_glyph = be_u32(self.data, group + 8)
      return start_glyph + (code - start)
    }
  }
  0
}
