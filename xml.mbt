///|
/// A small, purpose-built XML emitter.
///
/// OFD documents are XML with a fixed, shallow schema, so a DOM is overkill.
/// This writer is imperative: `open` / `leaf` / `close`, with escaping handled
/// in one place so no caller can forget it.

///|
pub struct Xml {
  sb : StringBuilder
  mut depth : Int32
}

///|
pub fn Xml::new() -> Xml {
  { sb: StringBuilder(), depth: 0, }
}

///|
fn Xml::indent(self : Xml) -> Unit {
  for _ in 0..<self.depth {
    self.sb.write_stringview("  ")
  }
}

///|
fn Xml::newline(self : Xml) -> Unit {
  self.sb.write_stringview("\n")
}

///|
/// Escape a string for use in XML text or a double-quoted attribute value.
pub fn xml_escape(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '&' => out.write_stringview("&amp;")
      '<' => out.write_stringview("&lt;")
      '>' => out.write_stringview("&gt;")
      '"' => out.write_stringview("&quot;")
      '\'' => out.write_stringview("&apos;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn Xml::write_attrs(self : Xml, attrs : Array[(String, String)]) -> Unit {
  for pair in attrs {
    let (key, value) = pair
    self.sb.write_stringview(" ")
    self.sb.write_stringview(key)
    self.sb.write_stringview("=\"")
    self.sb.write_stringview(xml_escape(value))
    self.sb.write_stringview("\"")
  }
}

///|
/// Emit the XML declaration. Call once, before anything else.
pub fn Xml::declaration(self : Xml) -> Unit {
  self.sb.write_stringview("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
}

///|
pub fn Xml::open(
  self : Xml,
  name : String,
  attrs : Array[(String, String)],
) -> Unit {
  self.indent()
  self.sb.write_stringview("<")
  self.sb.write_stringview(name)
  self.write_attrs(attrs)
  self.sb.write_stringview(">")
  self.newline()
  self.depth = self.depth + 1
}

///|
pub fn Xml::close(self : Xml, name : String) -> Unit {
  self.depth = self.depth - 1
  self.indent()
  self.sb.write_stringview("</")
  self.sb.write_stringview(name)
  self.sb.write_stringview(">")
  self.newline()
}

///|
/// A self-closing element.
pub fn Xml::empty(
  self : Xml,
  name : String,
  attrs : Array[(String, String)],
) -> Unit {
  self.indent()
  self.sb.write_stringview("<")
  self.sb.write_stringview(name)
  self.write_attrs(attrs)
  self.sb.write_stringview("/>")
  self.newline()
}

///|
/// An element whose body is a single text node.
pub fn Xml::leaf(
  self : Xml,
  name : String,
  attrs : Array[(String, String)],
  text : String,
) -> Unit {
  self.indent()
  self.sb.write_stringview("<")
  self.sb.write_stringview(name)
  self.write_attrs(attrs)
  self.sb.write_stringview(">")
  self.sb.write_stringview(xml_escape(text))
  self.sb.write_stringview("</")
  self.sb.write_stringview(name)
  self.sb.write_stringview(">")
  self.newline()
}

///|
pub fn Xml::to_string(self : Xml) -> String {
  self.sb.to_string()
}
