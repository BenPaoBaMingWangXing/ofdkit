///|
/// OFD package serialisation (GB/T 33190-2016).
///
/// The on-disk layout produced here is:
///
/// ```
/// OFD.xml                          entry point
/// Doc_0/Document.xml               document skeleton, page list
/// Doc_0/PublicRes.xml              shared resources: fonts
/// Doc_0/Pages/Page_0/Content.xml   page content stream
/// ```

///|
const OFD_NS : String = "http://www.ofdspec.org/2016"

///|
fn bool_attr(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn rect_attr(rect : Rect) -> String {
  "\{fmt_mm(rect.x)} \{fmt_mm(rect.y)} \{fmt_mm(rect.width)} \{fmt_mm(rect.height)}"
}

///|
fn box_attr(width : Double, height : Double) -> String {
  "0 0 \{fmt_mm(width)} \{fmt_mm(height)}"
}

///|
/// Serialise `OFD.xml`, the archive entry point.
pub fn serialize_ofd_xml(doc : Document) -> String {
  let xml = Xml::new()
  xml.declaration()
  xml.open("ofd:OFD", [
    ("xmlns:ofd", OFD_NS),
    ("DocType", "OFD"),
    ("Version", "1.1"),
  ])
  xml.open("ofd:DocBody", [])
  xml.open("ofd:DocInfo", [])
  xml.leaf("ofd:DocID", [], doc.doc_id)
  if doc.title != "" {
    xml.leaf("ofd:Title", [], doc.title)
  }
  if doc.author != "" {
    xml.leaf("ofd:Author", [], doc.author)
  }
  if doc.subject != "" {
    xml.leaf("ofd:Subject", [], doc.subject)
  }
  if doc.keywords != "" {
    xml.leaf("ofd:Keywords", [], doc.keywords)
  }
  xml.leaf("ofd:Creator", [], doc.creator)
  xml.leaf("ofd:CreationDate", [], doc.creation_date)
  xml.close("ofd:DocInfo")
  xml.leaf("ofd:DocRoot", [], "Doc_0/Document.xml")
  xml.close("ofd:DocBody")
  xml.close("ofd:OFD")
  xml.to_string()
}

///|
/// Serialise `Document.xml`, which lists the pages and points at resources.
pub fn serialize_document(doc : Document) -> String {
  let xml = Xml::new()
  xml.declaration()
  xml.open("ofd:Document", [("xmlns:ofd", OFD_NS)])
  xml.open("ofd:CommonData", [])
  // Element order follows what established OFD writers emit: page area first,
  // then resource references, then the id ceiling.
  xml.open("ofd:PageArea", [])
  let first = doc.pages[0]
  xml.leaf("ofd:PhysicalBox", [], box_attr(first.width, first.height))
  xml.leaf("ofd:ApplicationBox", [], box_attr(first.width, first.height))
  xml.close("ofd:PageArea")
  if doc.fonts.length() > 0 {
    xml.leaf("ofd:PublicRes", [], "PublicRes.xml")
  }
  xml.leaf("ofd:MaxUnitID", [], doc.max_unit_id().to_string())
  xml.close("ofd:CommonData")
  xml.open("ofd:Pages", [])
  for i, page in doc.pages {
    xml.empty("ofd:Page", [
      ("ID", page.id.to_string()),
      ("BaseLoc", "Pages/Page_\{i}/Content.xml"),
    ])
  }
  xml.close("ofd:Pages")
  xml.close("ofd:Document")
  xml.to_string()
}

///|
/// Serialise `PublicRes.xml`, the shared resource dictionary (fonts).
pub fn serialize_public_res(doc : Document) -> String {
  let xml = Xml::new()
  xml.declaration()
  xml.open("ofd:Res", [("xmlns:ofd", OFD_NS), ("BaseLoc", "Res")])
  if doc.fonts.length() > 0 {
    xml.open("ofd:Fonts", [])
    for font in doc.fonts {
      let attrs = [
        ("ID", font.id.to_string()),
        ("FontName", font.name),
        ("FamilyName", font.family),
        ("Charset", "unicode"),
      ]
      if font.data.length() > 0 {
        xml.open("ofd:Font", attrs)
        xml.leaf("ofd:FontFile", [], "Font_\{font.id}.ttf")
        xml.close("ofd:Font")
      } else {
        xml.empty("ofd:Font", attrs)
      }
    }
    xml.close("ofd:Fonts")
  }
  xml.close("ofd:Res")
  xml.to_string()
}

///|
fn serialize_text_object(xml : Xml, obj : TextObject) -> Unit {
  xml.open("ofd:TextObject", [
    ("ID", obj.id.to_string()),
    ("Boundary", rect_attr(obj.boundary)),
    ("Font", obj.font_id.to_string()),
    ("Size", fmt_mm(obj.size)),
    ("Fill", "true"),
  ])
  xml.empty("ofd:FillColor", [("Value", obj.color.to_value_string())])
  xml.leaf(
    "ofd:TextCode",
    [("X", fmt_mm(obj.offset_x)), ("Y", fmt_mm(obj.offset_y))],
    obj.text,
  )
  xml.close("ofd:TextObject")
}

///|
fn serialize_path_object(xml : Xml, obj : PathObject) -> Unit {
  xml.open("ofd:PathObject", [
    ("ID", obj.id.to_string()),
    ("Boundary", rect_attr(obj.boundary)),
    ("LineWidth", fmt_mm(obj.line_width)),
    ("Stroke", bool_attr(obj.stroke)),
    ("Fill", bool_attr(obj.fill)),
    ("Cap", "Round"),
    ("Join", "Round"),
  ])
  if obj.stroke {
    xml.empty("ofd:StrokeColor", [("Value", obj.stroke_color.to_value_string())])
  }
  if obj.fill {
    xml.empty("ofd:FillColor", [("Value", obj.fill_color.to_value_string())])
  }
  xml.leaf("ofd:AbbreviatedData", [], obj.data)
  xml.close("ofd:PathObject")
}

///|
/// Serialise one page's `Content.xml`.
pub fn serialize_content(page : Page) -> String {
  let xml = Xml::new()
  xml.declaration()
  xml.open("ofd:Page", [("xmlns:ofd", OFD_NS)])
  // No ofd:Area here: the page box is declared once in Document.xml, and
  // omitting the optional per-page area matches what common writers produce.
  xml.open("ofd:Content", [])
  xml.open("ofd:Layer", [("ID", (page.id * 1000 + 1).to_string())])
  for obj in page.objects {
    match obj {
      Text(t) => serialize_text_object(xml, t)
      Path(p) => serialize_path_object(xml, p)
    }
  }
  xml.close("ofd:Layer")
  xml.close("ofd:Content")
  xml.close("ofd:Page")
  xml.to_string()
}
