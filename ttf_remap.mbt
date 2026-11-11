///|
/// Renumbering subsetter.
///
/// The first version of `subset_font` kept original glyph ids and blanked the
/// ones a document did not use. That is safe but leaves `loca` and `hmtx` sized
/// for the whole font (28k glyphs), which is most of the remaining weight.
///
/// This pass renumbers: kept glyphs are packed into ids 0..n-1, and everything
/// that references a glyph id is rewritten — composite component indices,
/// `hmtx`, `cmap`, `maxp`, `post`.

///|
/// Map old glyph ids to new ones. Index is the old id, value the new id, -1 for
/// dropped glyphs.
fn build_remap(
  num_glyphs : Int32,
  keep : Array[Int32],
) -> (Array[Int32], Array[Int32]) {
  let sorted = keep.copy()
  sorted.sort()
  // Glyph 0 (.notdef) must stay at 0.
  let ordered : Array[Int32] = [0]
  for id in sorted {
    if id != 0 && !ordered.contains(id) {
      ordered.push(id)
    }
  }
  let old_to_new : Array[Int32] = Array::make(num_glyphs, -1)
  for new_id, old_id in ordered {
    if old_id >= 0 && old_id < num_glyphs {
      old_to_new[old_id] = new_id
    }
  }
  (ordered, old_to_new)
}

///|
/// Copy one glyph, rewriting composite component indices through `old_to_new`.
fn remap_glyph(
  face : TtfFace,
  old_id : Int32,
  old_to_new : Array[Int32],
) -> Bytes {
  match face.glyph_range(old_id) {
    None => Bytes::new(0)
    Some((start, length)) => {
      let out = FixedArray::make(length, b'\x00')
      for i in 0..<length {
        out[i] = face.data[start + i]
      }
      if be_i16(face.data, start) < 0 {
        // Composite glyph: walk the component list and patch glyphIndex.
        let mut pos = 10
        let mut more = true
        while more && pos + 4 <= length {
          let flags = be_u16(face.data, start + pos)
          let component_old = be_u16(face.data, start + pos + 2)
          let component_new = if component_old < old_to_new.length() {
            old_to_new[component_old]
          } else {
            -1
          }
          if component_new >= 0 {
            out[pos + 2] = ((component_new >> 8) & 0xFF).to_byte()
            out[pos + 3] = (component_new & 0xFF).to_byte()
          }
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
      Bytes::from_array(out[:])
    }
  }
}

///|
/// Build `glyf` and `loca` for the renumbered glyph order.
fn build_renumbered_glyf(
  face : TtfFace,
  ordered : Array[Int32],
  old_to_new : Array[Int32],
) -> (Bytes, Bytes, Bool) {
  let glyf = ByteBuf::new()
  let offsets : Array[Int32] = []
  for old_id in ordered {
    while glyf.length() % 4 != 0 {
      glyf.write_byte(b'\x00')
    }
    offsets.push(glyf.length())
    let data = remap_glyph(face, old_id, old_to_new)
    glyf.write_bytes(data)
  }
  while glyf.length() % 4 != 0 {
    glyf.write_byte(b'\x00')
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
/// Build `hmtx` for the new glyph order. Every glyph gets an entry
/// (`numberOfHMetrics == numGlyphs`), which `hhea` must agree with.
fn build_hmtx(face : TtfFace, ordered : Array[Int32]) -> Bytes {
  let hmtx = ByteBuf::new()
  let source = face.table("hmtx")
  for old_id in ordered {
    let advance = face.advance_width(old_id)
    let mut lsb = 0
    match source {
      None => ()
      Some(table) => {
        let metrics = face.number_of_hmetrics()
        // Glyphs past numberOfHMetrics store only a left side bearing, packed
        // in a trailing array. CJK fonts often have far fewer long metrics than
        // glyphs, so this branch is the common one for Chinese text.
        let at = if old_id < metrics {
          table.offset + old_id * 4 + 2
        } else {
          table.offset + metrics * 4 + (old_id - metrics) * 2
        }
        if at + 2 <= table.offset + table.length {
          lsb = be_i16(face.data, at)
        }
      }
    }
    hmtx.write_u16_be(advance.reinterpret_as_uint())
    hmtx.write_u16_be((lsb & 0xFFFF).reinterpret_as_uint())
  }
  hmtx.to_bytes()
}

///|
/// Rebuild `cmap` as a format 4 table containing only the mapped characters.
/// Code points above the BMP are dropped; a CJK document rarely needs them and
/// format 4 is what older readers are happiest with.
fn build_cmap4(pairs : Array[(Int32, Int32)]) -> (Bytes, Int32) {
  // Sort by code point and merge into one segment per run of consecutive codes
  // whose glyph ids also increment by one.
  let sorted = pairs.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
  let segments : Array[(Int32, Int32, Int32)] = []
  let dropped = 0
  for pair in sorted {
    let (code, glyph) = pair
    if code > 0xFFFF {
      continue
    }
    let last = segments.length() - 1
    if last >= 0 &&
      segments[last].1 + 1 == code &&
      segments[last].2 + (code - segments[last].0) == glyph {
      segments[last] = (segments[last].0, code, segments[last].2)
    } else {
      segments.push((code, code, glyph))
    }
  }
  // The terminating 0xFFFF segment is mandatory.
  segments.push((0xFFFF, 0xFFFF, 0))
  let seg_count = segments.length()
  let mut power = 1
  let mut log2 = 0
  while power * 2 <= seg_count {
    power = power * 2
    log2 = log2 + 1
  }
  let body = ByteBuf::new()
  body.write_u16_be(4U)
  body.write_u16_be(0U) // patched below once the size is known
  body.write_u16_be(0U) // language
  body.write_u16_be((seg_count * 2).reinterpret_as_uint())
  body.write_u16_be((power * 2).reinterpret_as_uint())
  body.write_u16_be(log2.reinterpret_as_uint())
  body.write_u16_be(((seg_count - power) * 2).reinterpret_as_uint())
  for segment in segments {
    body.write_u16_be(segment.1.reinterpret_as_uint())
  }
  body.write_u16_be(0U) // reservedPad
  for segment in segments {
    body.write_u16_be(segment.0.reinterpret_as_uint())
  }
  for segment in segments {
    // idDelta so that (code + delta) mod 65536 == glyph.
    let delta = (segment.2 - segment.0) & 0xFFFF
    body.write_u16_be(delta.reinterpret_as_uint())
  }
  for _ in segments {
    body.write_u16_be(0U) // idRangeOffset
  }
  let bytes = body.to_bytes()
  // Patch the length field.
  let fixed = FixedArray::make(bytes.length(), b'\x00')
  for i in 0..<bytes.length() {
    fixed[i] = bytes[i]
  }
  let total = bytes.length()
  fixed[2] = ((total >> 8) & 0xFF).to_byte()
  fixed[3] = (total & 0xFF).to_byte()
  (Bytes::from_array(fixed[:]), dropped)
}

///|
/// Build a format 12 subtable for code points beyond the BMP. Groups are runs
/// of consecutive code points whose glyph ids also increment by one.
fn build_cmap12(pairs : Array[(Int32, Int32)]) -> Bytes {
  let sorted = pairs.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
  let groups : Array[(Int32, Int32, Int32)] = []
  for pair in sorted {
    let (code, glyph) = pair
    let last = groups.length() - 1
    if last >= 0 &&
      groups[last].1 + 1 == code &&
      groups[last].2 + (code - groups[last].0) == glyph {
      groups[last] = (groups[last].0, code, groups[last].2)
    } else {
      groups.push((code, code, glyph))
    }
  }
  let length = 16 + groups.length() * 12
  let body = ByteBuf::new()
  body.write_u16_be(12U) // format
  body.write_u16_be(0U) // reserved
  body.write_u32_be(length.reinterpret_as_uint())
  body.write_u32_be(0U) // language
  body.write_u32_be(groups.length().reinterpret_as_uint())
  for group in groups {
    body.write_u32_be(group.0.reinterpret_as_uint())
    body.write_u32_be(group.1.reinterpret_as_uint())
    body.write_u32_be(group.2.reinterpret_as_uint())
  }
  body.to_bytes()
}

///|
/// Wrap a subtable in a `cmap` table with one Windows Unicode encoding record.
/// Format 4 uses encoding id 1 (BMP), format 12 uses 10 (full repertoire).
fn wrap_cmap(subtable : Bytes) -> Bytes {
  let format = be_u16(subtable, 0)
  let encoding : UInt32 = if format == 12 { 10U } else { 1U }
  let cmap = ByteBuf::new()
  cmap.write_u16_be(0U) // version
  cmap.write_u16_be(1U) // numTables
  cmap.write_u16_be(3U) // platformID: Windows
  cmap.write_u16_be(encoding)
  cmap.write_u32_be(12U) // offset to subtable
  cmap.write_bytes(subtable)
  cmap.to_bytes()
}

///|
/// A minimal `post` table: version 3 means "no glyph names", which is 32 bytes
/// instead of a name index nobody uses.
fn empty_post_table() -> Bytes {
  let post = ByteBuf::new()
  post.write_u32_be(0x00030000U)
  post.write_u32_be(0U) // italicAngle
  post.write_u16_be(0U) // underlinePosition
  post.write_u16_be(0U) // underlineThickness
  post.write_u32_be(0U) // isFixedPitch
  post.write_u32_be(0U) // minMemType42
  post.write_u32_be(0U) // maxMemType42
  post.write_u32_be(0U) // minMemType1
  post.write_u32_be(0U) // maxMemType1
  post.to_bytes()
}

///|
/// Patch `maxp` so `numGlyphs` matches the new order.
fn patch_maxp(face : TtfFace, num_glyphs : Int32) -> Bytes? {
  match face.table("maxp") {
    None => None
    Some(table) => {
      let data = slice_of(face.data, table.offset, table.length)
      let fixed = FixedArray::make(data.length(), b'\x00')
      for i in 0..<data.length() {
        fixed[i] = data[i]
      }
      if data.length() >= 6 {
        fixed[4] = ((num_glyphs >> 8) & 0xFF).to_byte()
        fixed[5] = (num_glyphs & 0xFF).to_byte()
      }
      Some(Bytes::from_array(fixed[:]))
    }
  }
}

///|
/// Subset `face` down to `code_points`, renumbering glyphs so tables are sized
/// for what is kept rather than for the whole font.
pub fn subset_font_renumbered(
  face : TtfFace,
  code_points : Array[Int32],
) -> Result[Bytes, String] {
  let num_glyphs = face.num_glyphs()
  if num_glyphs == 0 {
    return Err("font has no glyphs (missing maxp table)")
  }
  // Code point -> old glyph id.
  let pairs : Array[(Int32, Int32)] = []
  let wanted : Array[Int32] = [0]
  for code in code_points {
    let glyph = face.glyph_for_char(code)
    if glyph != 0 && !wanted.contains(glyph) {
      wanted.push(glyph)
      pairs.push((code, glyph))
    }
  }
  let keep = close_over_components(face, wanted)
  let (ordered, old_to_new) = build_remap(num_glyphs, keep)
  // Remap the recorded pairs to new ids.
  let remapped : Array[(Int32, Int32)] = []
  for pair in pairs {
    let new_id = old_to_new[pair.1]
    if new_id >= 0 {
      remapped.push((pair.0, new_id))
    }
  }
  let (glyf, loca, short_format) = build_renumbered_glyf(
    face, ordered, old_to_new,
  )
  let hmtx = build_hmtx(face, ordered)
  // Format 4 is what every reader understands, but it cannot express code
  // points above the BMP. Fall back to format 12 only when the document needs
  // it, so ordinary Chinese text keeps the widest compatibility.
  let mut needs_wide = false
  for pair in remapped {
    if pair.0 > 0xFFFF {
      needs_wide = true
    }
  }
  let cmap_subtable = if needs_wide {
    build_cmap12(remapped)
  } else {
    let (subtable, _) = build_cmap4(remapped)
    subtable
  }
  let cmap = wrap_cmap(cmap_subtable)

  let out : Array[OutTable] = []
  let head = match head_with_loca_format(face, !short_format) {
    None => return Err("font has no usable head table")
    Some(data) => data
  }
  out.push({ tag: "head", data: head, checksum: table_checksum(head), })
  let maxp = match patch_maxp(face, ordered.length()) {
    None => return Err("font has no usable maxp table")
    Some(data) => data
  }
  out.push({ tag: "maxp", data: maxp, checksum: table_checksum(maxp), })
  // hhea must agree with hmtx: numberOfHMetrics == numGlyphs.
  let hhea = match face.table("hhea") {
    None => return Err("font has no usable hhea table")
    Some(table) => {
      let data = slice_of(face.data, table.offset, table.length)
      let fixed = FixedArray::make(data.length(), b'\x00')
      for i in 0..<data.length() {
        fixed[i] = data[i]
      }
      let metrics = ordered.length()
      if data.length() >= 36 {
        fixed[34] = ((metrics >> 8) & 0xFF).to_byte()
        fixed[35] = (metrics & 0xFF).to_byte()
      }
      Bytes::from_array(fixed[:])
    }
  }
  out.push({ tag: "hhea", data: hhea, checksum: table_checksum(hhea), })
  out.push({ tag: "hmtx", data: hmtx, checksum: table_checksum(hmtx), })
  out.push({ tag: "cmap", data: cmap, checksum: table_checksum(cmap), })
  out.push({ tag: "loca", data: loca, checksum: table_checksum(loca), })
  out.push({ tag: "glyf", data: glyf, checksum: table_checksum(glyf), })
  let post = empty_post_table()
  out.push({ tag: "post", data: post, checksum: table_checksum(post), })
  // Keeping the hinting programs costs a few KB and restores the small-size
  // rasterisation the original font had. Hinting references cvt entries and
  // points within a glyph, never glyph ids, so renumbering does not break it.
  for tag in ["name", "OS/2", "gasp", "cvt ", "fpgm", "prep"] {
    match copy_table(face, tag) {
      None => ()
      Some(table) => out.push(table)
    }
  }
  Ok(assemble_sfnt(out))
}
