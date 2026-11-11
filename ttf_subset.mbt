///|
/// TrueType subsetting for embedding.
///
/// Strategy: keep glyph ids unchanged and blank out the ones the document does
/// not use. That keeps `cmap`, `hmtx` and — crucially — composite glyph
/// component indices valid without any renumbering, which is where most
/// subsetters break. `glyf` and `loca` are rebuilt; everything else is copied.
///
/// The result is a smaller but otherwise ordinary TrueType file. Glyphs that
/// were dropped simply render as blank, which is fine: the document that
/// produced the subset never asks for them.

///|
priv struct OutTable {
  tag : String
  data : Bytes
  checksum : UInt32
}

///|
fn pad4(n : Int32) -> Int32 {
  (n + 3) / 4 * 4
}

///|
fn table_checksum(data : Bytes) -> UInt32 {
  let mut sum = 0U
  let n = data.length()
  let padded = pad4(n)
  let mut i = 0
  while i < padded {
    let b0 = if i < n { data[i].to_uint() } else { 0U }
    let b1 = if i + 1 < n { data[i + 1].to_uint() } else { 0U }
    let b2 = if i + 2 < n { data[i + 2].to_uint() } else { 0U }
    let b3 = if i + 3 < n { data[i + 3].to_uint() } else { 0U }
    sum = sum + ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    i = i + 4
  }
  sum
}

///|
fn slice_of(data : Bytes, start : Int32, length : Int32) -> Bytes {
  let tmp = FixedArray::make(length, b'\x00')
  for i in 0..<length {
    tmp[i] = data[start + i]
  }
  Bytes::from_array(tmp[:])
}

///|
/// Collect component glyph ids referenced by a composite glyph.
fn collect_components(
  face : TtfFace,
  start : Int32,
  length : Int32,
  out : Array[Int32],
) -> Unit {
  if length < 10 {
    return
  }
  let contours = be_i16(face.data, start)
  if contours >= 0 {
    return
  }
  let mut pos = start + 10
  let mut more = true
  while more {
    if pos + 4 > start + length {
      return
    }
    let flags = be_u16(face.data, pos)
    let glyph = be_u16(face.data, pos + 2)
    out.push(glyph)
    let mut step = 4
    if (flags & 0x0001) != 0 {
      step = step + 4
    } else {
      step = step + 2
    }
    if (flags & 0x0008) != 0 {
      step = step + 2
    } else if (flags & 0x0040) != 0 {
      step = step + 4
    } else if (flags & 0x0080) != 0 {
      step = step + 8
    }
    pos = pos + step
    more = (flags & 0x0020) != 0
  }
}

///|
/// Expand `glyphs` with every composite component they transitively reference.
fn close_over_components(face : TtfFace, glyphs : Array[Int32]) -> Array[Int32] {
  let seen : Array[Int32] = []
  let queue : Array[Int32] = []
  for glyph in glyphs {
    if !seen.contains(glyph) {
      seen.push(glyph)
      queue.push(glyph)
    }
  }
  let mut cursor = 0
  while cursor < queue.length() {
    let id = queue[cursor]
    cursor = cursor + 1
    match face.glyph_range(id) {
      None => ()
      Some((start, length)) => {
        let parts : Array[Int32] = []
        collect_components(face, start, length, parts)
        for part in parts {
          if !seen.contains(part) {
            seen.push(part)
            queue.push(part)
          }
        }
      }
    }
  }
  seen
}

///|
/// Build a `glyf` table containing only `keep` glyphs, plus the matching `loca`.
/// `loca` uses the short format when the glyph data fits in 16-bit doubled
/// offsets, which halves that table — it is sized by glyph count, not by how
/// many glyphs we kept. Returns `(glyf, loca, used_short_format)`.
fn build_glyf_loca(face : TtfFace, keep : Array[Int32]) -> (Bytes, Bytes, Bool) {
  let num_glyphs = face.num_glyphs()
  let glyf = ByteBuf::new()
  let offsets : Array[Int32] = []
  for id in 0..<num_glyphs {
    offsets.push(glyf.length())
    if keep.contains(id) {
      match face.glyph_range(id) {
        None => ()
        Some((start, length)) => {
          // Glyph data must stay 4-byte aligned inside glyf.
          while glyf.length() % 4 != 0 {
            glyf.write_byte(b'\x00')
          }
          offsets[offsets.length() - 1] = glyf.length()
          glyf.write_bytes(slice_of(face.data, start, length))
        }
      }
    }
  }
  offsets.push(glyf.length())
  let short_format = glyf.length() <= 131070
  let loca = ByteBuf::new()
  for offset in offsets {
    if short_format {
      loca.write_u16_be((offset / 2).reinterpret_as_uint())
    } else {
      loca.write_u32_be(offset.reinterpret_as_uint())
    }
  }
  (glyf.to_bytes(), loca.to_bytes(), short_format)
}

///|
/// Copy a table verbatim from the source font.
fn copy_table(face : TtfFace, tag : String) -> OutTable? {
  match face.table(tag) {
    None => None
    Some(table) => {
      let data = slice_of(face.data, table.offset, table.length)
      Some({ tag, data, checksum: table_checksum(data), })
    }
  }
}

///|
/// Tables copied unchanged into the subset. Hinting programs (`cvt`, `fpgm`,
/// `prep`) and the vertical metrics are dropped: the subset is meant for
/// printed layout, where those add weight without helping.
let copied_tables : Array[String] = [
  "head", "hhea", "hmtx", "maxp", "cmap", "name", "post", "OS/2", "gasp",
]

///|
/// Rewrite `head` so `indexToLocFormat` matches the `loca` we emit, then zero
/// the checksum adjustment; the value is recomputed by consumers that care.
fn head_with_loca_format(face : TtfFace, long_format : Bool) -> Bytes? {
  match face.table("head") {
    None => None
    Some(table) => {
      if table.length < 54 {
        return None
      }
      let data = slice_of(face.data, table.offset, table.length)
      let tmp = FixedArray::make(data.length(), b'\x00')
      for i in 0..<data.length() {
        tmp[i] = data[i]
      }
      // indexToLocFormat at offset 50, big endian.
      tmp[50] = b'\x00'
      tmp[51] = if long_format { b'\x01' } else { b'\x00' }
      // checkSumAdjustment at offset 8.
      for i in 0..<4 {
        tmp[8 + i] = b'\x00'
      }
      Some(Bytes::from_array(tmp[:]))
    }
  }
}

///|
/// Assemble the sfnt file from an ordered table list.
fn assemble_sfnt(tables : Array[OutTable]) -> Bytes {
  let sorted = tables.copy()
  sorted.sort_by(fn(a, b) { a.tag.compare(b.tag) })
  let count = sorted.length()
  let header = ByteBuf::new()
  header.write_u32_be(0x00010000U)
  header.write_u16_be(count.reinterpret_as_uint())
  // searchRange / entrySelector / rangeShift, per the OpenType spec.
  let mut power = 1
  let mut log2 = 0
  while power * 2 <= count {
    power = power * 2
    log2 = log2 + 1
  }
  header.write_u16_be((power * 16).reinterpret_as_uint())
  header.write_u16_be(log2.reinterpret_as_uint())
  header.write_u16_be((count * 16 - power * 16).reinterpret_as_uint())
  let body = ByteBuf::new()
  let records : Array[(String, UInt32, UInt32, UInt32)] = []
  let base = 12 + count * 16
  for table in sorted {
    let offset = base + body.length()
    records.push(
      (
        table.tag,
        table.checksum,
        offset.reinterpret_as_uint(),
        table.data.length().reinterpret_as_uint(),
      ),
    )
    body.write_bytes(table.data)
    while body.length() % 4 != 0 {
      body.write_byte(b'\x00')
    }
  }
  for record in records {
    let (tag, checksum, offset, length) = record
    header.write_ascii(tag)
    header.write_u32_be(checksum)
    header.write_u32_be(offset)
    header.write_u32_be(length)
  }
  header.write_bytes(body.to_bytes())
  header.to_bytes()
}

///|
/// Build a subset font that can render exactly `code_points` (plus whatever
/// glyphs those need as composite components).
pub fn subset_font(
  face : TtfFace,
  code_points : Array[Int32],
) -> Result[Bytes, String] {
  if face.num_glyphs() == 0 {
    return Err("font has no glyphs (missing maxp table)")
  }
  let wanted : Array[Int32] = [0]
  for code in code_points {
    let glyph = face.glyph_for_char(code)
    if glyph != 0 && !wanted.contains(glyph) {
      wanted.push(glyph)
    }
  }
  let keep = close_over_components(face, wanted)
  let (glyf, loca, short_format) = build_glyf_loca(face, keep)
  let out : Array[OutTable] = []
  let head = match head_with_loca_format(face, !short_format) {
    None => return Err("font has no usable head table")
    Some(data) => data
  }
  out.push({ tag: "head", data: head, checksum: table_checksum(head), })
  for tag in copied_tables {
    if tag == "head" {
      continue
    }
    match copy_table(face, tag) {
      None => ()
      Some(table) => out.push(table)
    }
  }
  out.push({ tag: "loca", data: loca, checksum: table_checksum(loca), })
  out.push({ tag: "glyf", data: glyf, checksum: table_checksum(glyf), })
  if out.length() > 4095 {
    return Err("too many tables")
  }
  Ok(assemble_sfnt(out))
}
