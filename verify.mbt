///|
/// Structural verification of an OFD package.
///
/// This is the project's own conformance gate: it re-reads what we wrote and
/// checks the invariants the standard requires (entry point present, doc root
/// resolvable, every page locatable, declared resources actually shipped).
/// It is intentionally strict about structure and silent about rendering.

///|
pub struct VerifyCheck {
  name : String
  passed : Bool
  detail : String
}

///|
pub struct VerifyReport {
  checks : Array[VerifyCheck]
}

///|
fn VerifyReport::add(
  self : VerifyReport,
  name : String,
  passed : Bool,
  detail : String,
) -> Unit {
  self.checks.push({ name, passed, detail, })
}

///|
pub fn VerifyReport::passed(self : VerifyReport) -> Bool {
  for check in self.checks {
    if !check.passed {
      return false
    }
  }
  true
}

///|
pub fn VerifyReport::failures(self : VerifyReport) -> Array[VerifyCheck] {
  self.checks.filter(fn(check) { !check.passed })
}

///|
pub fn VerifyReport::summary(self : VerifyReport) -> String {
  let mut total = 0
  let mut ok = 0
  for check in self.checks {
    total = total + 1
    if check.passed {
      ok = ok + 1
    }
  }
  "\{ok}/\{total} checks passed"
}

///|
/// Return the text between the first `<tag>` and the next `</tag>`.
fn tag_inner(xml : String, tag : String) -> String? {
  let open = "<\{tag}>"
  let close = "</\{tag}>"
  match xml.find(open) {
    None => None
    Some(start_pos) => {
      let start = start_pos + open.length()
      let rest = xml[start:]
      match rest.find(close) {
        None => None
        Some(end_pos) => Some(rest[:end_pos].to_owned())
      }
    }
  }
}

///|
/// Collect the text of every `<tag>...</tag>` occurrence in document order.
fn find_all_tag_inner(xml : String, tag : String) -> Array[String] {
  let values : Array[String] = []
  let open = "<\{tag}>"
  let close = "</\{tag}>"
  let mut rest = xml
  let mut keep_going = true
  while keep_going {
    match rest.find(open) {
      None => keep_going = false
      Some(start_pos) => {
        let after_open = rest[start_pos + open.length():]
        match after_open.find(close) {
          None => keep_going = false
          Some(end_pos) => {
            values.push(after_open[:end_pos].to_owned())
            rest = after_open[end_pos + close.length():].to_owned()
          }
        }
      }
    }
  }
  values
}

///|
/// Collect every value of `attr="..."` in document order.
fn find_all_attr(xml : String, attr : String) -> Array[String] {
  let values : Array[String] = []
  let needle = attr + "=\""
  let mut rest = xml
  let mut keep_going = true
  while keep_going {
    match rest.find(needle) {
      None => keep_going = false
      Some(pos) => {
        let start = pos + needle.length()
        let tail = rest[start:]
        match tail.find("\"") {
          None => keep_going = false
          Some(end_pos) => {
            values.push(tail[:end_pos].to_owned())
            let consumed = start + end_pos + 1
            rest = rest[consumed:].to_owned()
          }
        }
      }
    }
  }
  values
}

///|
/// Text content of every `<tag ...>...</tag>` element, in document order.
/// `find_all_tag_inner` only matches opening tags without attributes; element
/// text such as `ofd:TextCode` always carries `X`/`Y`, so it needs this one.
fn find_all_element_text(xml : String, tag : String) -> Array[String] {
  let values : Array[String] = []
  let open = "<" + tag
  let close = "</" + tag + ">"
  let mut rest = xml
  let mut keep_going = true
  while keep_going {
    match rest.find(open) {
      None => keep_going = false
      Some(pos) => {
        let after = rest[pos + open.length():]
        match after.find(">") {
          None => keep_going = false
          Some(gt) => {
            let body = after[gt + 1:]
            match body.find(close) {
              None => keep_going = false
              Some(end) => {
                values.push(body[:end].to_owned())
                rest = body[end + close.length():].to_owned()
              }
            }
          }
        }
      }
    }
  }
  values
}

///|
/// Undo the five predefined XML entities, which is everything `xml_escape`
/// ever produces.
fn xml_unescape(text : String) -> String {
  if !text.contains("&") {
    return text
  }
  let out = StringBuilder()
  let mut rest = text
  let mut keep_going = true
  while keep_going {
    match rest.find("&") {
      None => {
        out.write_stringview(rest)
        keep_going = false
      }
      Some(pos) => {
        out.write_stringview(rest[:pos])
        let tail = rest[pos:]
        if tail.has_prefix("&amp;") {
          out.write_char('&')
          rest = tail[5:].to_owned()
        } else if tail.has_prefix("&lt;") {
          out.write_char('<')
          rest = tail[4:].to_owned()
        } else if tail.has_prefix("&gt;") {
          out.write_char('>')
          rest = tail[4:].to_owned()
        } else if tail.has_prefix("&quot;") {
          out.write_char('"')
          rest = tail[6:].to_owned()
        } else if tail.has_prefix("&apos;") {
          out.write_char('\'')
          rest = tail[6:].to_owned()
        } else {
          out.write_char('&')
          rest = tail[1:].to_owned()
        }
      }
    }
  }
  out.to_string()
}

///|

///|
/// Verify an OFD package held in memory.
pub fn verify_ofd(data : Bytes) -> VerifyReport {
  let report = { checks: [], }
  match parse_zip(data) {
    Err(message) => {
      report.add("zip container parses", false, message)
      return report
    }
    Ok(archive) => {
      report.add(
        "zip container parses",
        true,
        "\{archive.names().length()} entries",
      )
      // Entry point.
      let ofd_xml = match archive.read("OFD.xml") {
        Err(message) => {
          report.add("OFD.xml present", false, message)
          return report
        }
        Ok(bytes) => {
          report.add("OFD.xml present", true, "at archive root")
          @utf8.decode_lossy(bytes)
        }
      }
      let has_root = ofd_xml.contains("<ofd:OFD")
      report.add("OFD.xml declares ofd:OFD", has_root, "")
      // Document root.
      let doc_root = match tag_inner(ofd_xml, "ofd:DocRoot") {
        None => {
          report.add("DocRoot declared", false, "missing ofd:DocRoot")
          return report
        }
        Some(value) => {
          report.add("DocRoot declared", true, value)
          value
        }
      }
      let document_xml = match archive.read(doc_root) {
        Err(message) => {
          report.add("DocRoot resolves", false, message)
          return report
        }
        Ok(bytes) => {
          report.add("DocRoot resolves", true, doc_root)
          @utf8.decode_lossy(bytes)
        }
      }
      report.add(
        "Document.xml declares ofd:Document",
        document_xml.contains("<ofd:Document"),
        "",
      )
      // The page box lives once in Document.xml / CommonData / PageArea.
      let page_box = tag_inner(document_xml, "ofd:PhysicalBox")
      report.add(
        "document declares a page box",
        page_box is Some(_),
        match page_box {
          Some(value) => value
          None => "missing ofd:PhysicalBox"
        },
      )
      // Pages.
      let base_locs = find_all_attr(document_xml, "BaseLoc")
      if base_locs.length() == 0 {
        report.add("document has pages", false, "no BaseLoc entries")
      } else {
        report.add("document has pages", true, "\{base_locs.length()} page(s)")
        let doc_dir = parent_dir(doc_root)
        let mut all_present = true
        let mut first_missing = ""
        for base_loc in base_locs {
          let path = join_path(doc_dir, base_loc)
          if !archive.contains(path) {
            all_present = false
            if first_missing == "" {
              first_missing = path
            }
          }
        }
        report.add(
          "every page content stream exists", all_present, first_missing,
        )
      }
      // Outline destinations must point at a page that exists.
      let outline_dests = find_all_tag_inner(document_xml, "ofd:Dest")
      if outline_dests.length() == 0 {
        report.add("no outline entries", true, "")
      } else {
        let mut dangling = ""
        for dest in outline_dests {
          // A destination must name a page, not merely any element with that id.
          if !document_xml.contains("ofd:Page ID=\"\{dest}\"") {
            dangling = dest
          }
        }
        report.add(
          "outline destinations resolve",
          dangling == "",
          if dangling == "" {
            "\{outline_dests.length()} entr(ies)"
          } else {
            "dangling page id \{dangling}"
          },
        )
      }
      // Shared resources.
      match tag_inner(document_xml, "ofd:PublicRes") {
        None => report.add("shared resources absent", true, "no fonts declared")
        Some(res_name) => {
          let res_path = join_path(parent_dir(doc_root), res_name)
          match archive.read(res_path) {
            Err(message) => report.add("PublicRes resolves", false, message)
            Ok(bytes) => {
              report.add("PublicRes resolves", true, res_path)
              let res_xml = @utf8.decode_lossy(bytes)
              let font_files = find_all_tag_inner(res_xml, "ofd:FontFile")
              // FontFile values are relative to the directory named by BaseLoc
              // on the ofd:Res element, which is "Res" for packages we write.
              let mut missing = ""
              let mut all_fonts = true
              for file in font_files {
                let candidate = join_path(parent_dir(res_path), "Res/\{file}")
                if !archive.contains(candidate) {
                  all_fonts = false
                  if missing == "" {
                    missing = candidate
                  }
                }
              }
              report.add(
                "declared font files are packaged",
                all_fonts,
                if font_files.length() == 0 {
                  "no embedded fonts"
                } else if missing == "" {
                  "\{font_files.length()} font file(s)"
                } else {
                  missing
                },
              )
              // A packaged font must actually be a font. This catches the case
              // where the file exists but the subsetter emitted garbage.
              let mut fonts_ok = true
              let mut font_detail = if font_files.length() == 0 {
                "no embedded fonts"
              } else {
                ""
              }
              // Keep the parsed faces: the character-coverage check below needs
              // their cmaps.
              let faces : Array[TtfFace] = []
              for file in font_files {
                let candidate = join_path(parent_dir(res_path), "Res/\{file}")
                match archive.read(candidate) {
                  Err(message) => {
                    fonts_ok = false
                    font_detail = message
                  }
                  Ok(bytes) =>
                    match parse_ttf(bytes) {
                      Err(message) => {
                        fonts_ok = false
                        font_detail = "\{file}: \{message}"
                      }
                      Ok(face) => {
                        font_detail = "\{file}: \{face.num_glyphs()} glyphs"
                        faces.push(face)
                      }
                    }
                }
              }
              report.add("embedded fonts are readable", fonts_ok, font_detail)

              // Every character the content streams draw has to exist in the
              // embedded subset. A missing glyph renders as a blank box, and no
              // structural check can see that, so check it here.
              if font_files.length() == 0 {
                report.add(
                  "every drawn character is embedded", true, "no embedded font; the reader falls back to a system font",
                )
              } else if !fonts_ok {
                report.add(
                  "every drawn character is embedded", false, "font files could not be parsed",
                )
              } else {
                let doc_dir = parent_dir(doc_root)
                let mut total = 0
                let missing : Array[Char] = []
                for base_loc in base_locs {
                  let path = join_path(doc_dir, base_loc)
                  match archive.read(path) {
                    Err(_) => ()
                    Ok(bytes) => {
                      let content = @utf8.decode_lossy(bytes)
                      for raw in find_all_element_text(content, "ofd:TextCode") {
                        for ch in xml_unescape(raw) {
                          if ch == '\n' || ch == '\r' {
                            continue
                          }
                          total = total + 1
                          let mut covered = false
                          for face in faces {
                            if face.glyph_for_char(
                                ch.to_uint().reinterpret_as_int(),
                              ) !=
                              0 {
                              covered = true
                            }
                          }
                          if !covered && !missing.contains(ch) {
                            missing.push(ch)
                          }
                        }
                      }
                    }
                  }
                }
                if total == 0 {
                  report.add(
                    "every drawn character is embedded", true, "no text drawn",
                  )
                } else if missing.length() == 0 {
                  report.add(
                    "every drawn character is embedded",
                    true,
                    "\{total} character(s) covered",
                  )
                } else {
                  let sample = StringBuilder()
                  let limit = if missing.length() < 8 {
                    missing.length()
                  } else {
                    8
                  }
                  for i in 0..<limit {
                    if i > 0 {
                      sample.write_char(' ')
                    }
                    sample.write_char(missing[i])
                  }
                  report.add(
                    "every drawn character is embedded",
                    false,
                    "\{missing.length()} of \{total} character(s) missing from the subset: \{sample.to_string()}",
                  )
                }
              }
            }
          }
        }
      }
      // Document-level resources: images.
      match tag_inner(document_xml, "ofd:DocumentRes") {
        None => report.add("no image resources", true, "")
        Some(res_name) => {
          let res_path = join_path(parent_dir(doc_root), res_name)
          match archive.read(res_path) {
            Err(message) => report.add("DocumentRes resolves", false, message)
            Ok(bytes) => {
              report.add("DocumentRes resolves", true, res_path)
              let doc_res_xml = @utf8.decode_lossy(bytes)
              let image_files = find_all_tag_inner(doc_res_xml, "ofd:ImageFile")
              let mut missing = ""
              let mut all_images = true
              let mut bad_format = ""
              let mut count = 0
              for file in image_files {
                count = count + 1
                let candidate = join_path(parent_dir(res_path), "Res/\{file}")
                if !archive.contains(candidate) {
                  all_images = false
                  if missing == "" {
                    missing = candidate
                  }
                } else {
                  match archive.read(candidate) {
                    Err(message) => {
                      all_images = false
                      bad_format = message
                    }
                    Ok(data) =>
                      match detect_image_format(data) {
                        Err(message) => {
                          all_images = false
                          bad_format = "\{file}: \{message}"
                        }
                        Ok(_) => ()
                      }
                  }
                }
              }
              report.add(
                "declared images are packaged",
                all_images,
                if count == 0 {
                  "no images"
                } else if missing == "" {
                  "\{count} image(s)"
                } else {
                  missing
                },
              )
              report.add(
                "images are PNG or JPEG",
                bad_format == "",
                if count == 0 {
                  "no images"
                } else if bad_format == "" {
                  "\{count} image(s)"
                } else {
                  bad_format
                },
              )
            }
          }
        }
      }
      report
    }
  }
}

///|
/// Directory part of a package path, or "" when the file sits at the root.
fn parent_dir(path : String) -> String {
  let parts = path.split("/").collect()
  if parts.length() <= 1 {
    return ""
  }
  let out = StringBuilder()
  for i in 0..<(parts.length() - 1) {
    if i > 0 {
      out.write_char('/')
    }
    out.write_stringview(parts[i])
  }
  out.to_string()
}

///|
fn join_path(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else {
    "\{dir}/\{name}"
  }
}
