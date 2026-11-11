#!/usr/bin/env python3
"""Independent structural check for an OFD package produced by ofdkit.

This script deliberately shares no code with the MoonBit implementation. It
unzips the package with the standard library and parses every XML part with
ElementTree, so a bug in ofdkit's own writer cannot mask itself here.

Usage:
    python3 scripts/verify_ofd.py out/demo.ofd
"""

import struct
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = {"ofd": "http://www.ofdspec.org/2016"}
REQUIRED = ["OFD.xml", "Doc_0/Document.xml"]


def fail(message: str) -> None:
    print(f"FAIL  {message}")
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]

    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as exc:
        fail(f"not a zip archive: {exc}")

    broken = archive.testzip()
    if broken is not None:
        fail(f"crc mismatch in entry {broken}")

    names = archive.namelist()
    print(f"entries: {len(names)}")
    for name in names:
        print(f"  {name}")

    for required in REQUIRED:
        if required not in names:
            fail(f"missing required entry {required}")

    # Every part must be well-formed XML in the OFD namespace.
    roots = {}
    for name in names:
        if not name.endswith(".xml"):
            continue
        try:
            root = ET.fromstring(archive.read(name).decode("utf-8"))
        except ET.ParseError as exc:
            fail(f"{name} is not well-formed XML: {exc}")
        if not root.tag.startswith(f"{{{NS['ofd']}}}"):
            fail(f"{name} is not in the OFD namespace: {root.tag}")
        roots[name] = root
        print(f"  xml ok  {name}  <{root.tag.split('}')[-1]}>")

    # OFD.xml must point at a document root that exists.
    doc_root = roots["OFD.xml"].find(".//ofd:DocRoot", NS)
    if doc_root is None or not doc_root.text:
        fail("OFD.xml has no DocRoot")
    doc_path = doc_root.text.strip()
    if doc_path not in names:
        fail(f"DocRoot points at a missing entry: {doc_path}")

    document = roots[doc_path]
    pages = document.findall(".//ofd:Page", NS)
    if not pages:
        fail("document declares no pages")

    # The page box is declared once in Document.xml.
    page_box = document.find(".//ofd:PageArea/ofd:PhysicalBox", NS)
    if page_box is None or not page_box.text:
        fail("Document.xml has no PageArea/PhysicalBox")
    box_width, box_height = page_box.text.split()[2:4]
    print(f"  page box  {box_width} x {box_height} mm")

    # Each page's BaseLoc must resolve, and the content stream must be a page.
    base_dir = doc_path.rsplit("/", 1)[0] if "/" in doc_path else ""
    for page in pages:
        base_loc = page.get("BaseLoc")
        if base_loc is None:
            fail("page is missing BaseLoc")
        page_path = f"{base_dir}/{base_loc}" if base_dir else base_loc
        if page_path not in names:
            fail(f"page BaseLoc does not resolve: {page_path}")
        page_root = roots[page_path]
        if not page_root.tag.endswith("}Page"):
            fail(f"{page_path} root is not ofd:Page")
        print(f"  page ok  {page_path}")

    # Embedded fonts must be real TrueType files, not renamed blobs.
    fonts = [n for n in names if n.lower().endswith(".ttf")]
    for name in fonts:
        data = archive.read(name)
        if len(data) < 12:
            fail(f"{name} is too short to be a font")
        version = struct.unpack(">I", data[:4])[0]
        if version not in (0x00010000, 0x74727565):
            fail(f"{name} is not a TrueType font (sfnt version 0x{version:08X})")
        table_count = struct.unpack(">H", data[4:6])[0]
        print(f"  font ok  {name}  {table_count} tables, {len(data)} bytes")

    # Outline destinations must reference a page that exists.
    outlines = document.findall(".//ofd:Outlines/ofd:Outline", NS)
    if outlines:
        page_ids = {p.get("ID") for p in pages}
        for outline in outlines:
            dest = outline.find(".//ofd:Dest", NS)
            if dest is None or (dest.text or "").strip() not in page_ids:
                fail(f"outline '{outline.get('Title')}' points at a missing page")
        print(f"  outline ok  {len(outlines)} entries")

    # Images must be PNG or JPEG; OFD readers pick a decoder by subtype.
    for name in names:
        lowered = name.lower()
        if not lowered.endswith((".png", ".jpg", ".jpeg")):
            continue
        data = archive.read(name)
        is_png = data[:4] == b"\x89PNG"
        is_jpeg = data[:3] == b"\xff\xd8\xff"
        if not (is_png or is_jpeg):
            fail(f"{name} is neither PNG nor JPEG")
        print(f"  image ok  {name}  {len(data)} bytes")

    # MaxUnitID must be at least as large as every object ID in the package.
    max_unit = document.find(".//ofd:MaxUnitID", NS)
    if max_unit is None or not max_unit.text:
        fail("document has no MaxUnitID")
    declared_max = int(max_unit.text)
    observed = 0
    for name, root in roots.items():
        for element in root.iter():
            identifier = element.get("ID")
            if identifier and identifier.isdigit():
                observed = max(observed, int(identifier))
    if observed > declared_max:
        fail(f"MaxUnitID {declared_max} is below an object ID {observed}")

    print(f"\nOK  {len(pages)} page(s), {len(names)} entries, MaxUnitID {declared_max}")


if __name__ == "__main__":
    main()
