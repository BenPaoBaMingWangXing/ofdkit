#!/usr/bin/env python3
"""Approximate an OFD page as a PNG, for eyeballing layout.

This is a *preview*, not a conformant renderer: it handles the subset of
objects ofdkit emits (text, straight paths, rectangles) and ignores everything
else. It exists so a layout can be checked without installing an OFD reader,
and so the README can show what the output looks like.

Usage:
    python3 scripts/preview_ofd.py out/demo.ofd out/preview.png [page-index]
"""

import sys
import zipfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

NS = {"ofd": "http://www.ofdspec.org/2016"}
SCALE = 4.0  # pixels per millimetre


def colour(element):
    if element is None:
        return None
    parts = (element.get("Value") or "").split()
    if len(parts) < 3:
        return None
    try:
        values = [int(float(p)) for p in parts[-3:]]
    except ValueError:
        return None
    return tuple(max(0, min(255, v)) for v in values)


def load_font(archive, doc_res_xml, size_px):
    """Use the embedded font when the package carries one."""
    if doc_res_xml is None:
        return ImageFont.load_default()
    fonts = [n for n in archive.namelist() if n.lower().endswith(".ttf")]
    if not fonts:
        return ImageFont.load_default()
    path = None
    import io

    data = archive.read(fonts[0])
    try:
        return ImageFont.truetype(io.BytesIO(data), size_px)
    except OSError:
        return ImageFont.load_default()


def parse_path(data, origin_x, origin_y):
    """Parse OFD abbreviated path data into a list of polylines."""
    tokens = data.replace(",", " ").split()
    lines = []
    current = []
    x = y = 0.0
    i = 0
    command = "M"
    while i < len(tokens):
        token = tokens[i]
        if token in ("M", "L", "C", "Q", "B"):
            command = token
            if command == "B" and current:
                lines.append(current)
                current = []
            i += 1
            continue
        if command == "M":
            if current:
                lines.append(current)
            x, y = float(tokens[i]), float(tokens[i + 1])
            current = [(origin_x + x, origin_y + y)]
            command = "L"
            i += 2
        elif command == "L":
            x, y = float(tokens[i]), float(tokens[i + 1])
            current.append((origin_x + x, origin_y + y))
            i += 2
        else:
            # Curves are flattened to their end point; good enough for a preview.
            if command == "C":
                x, y = float(tokens[i + 4]), float(tokens[i + 5])
                i += 6
            elif command == "Q":
                x, y = float(tokens[i + 2]), float(tokens[i + 3])
                i += 4
            else:
                i += 1
            current.append((origin_x + x, origin_y + y))
    if current:
        lines.append(current)
    return lines


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    ofd_path, png_path = sys.argv[1], sys.argv[2]
    page_index = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    archive = zipfile.ZipFile(ofd_path)
    document = ET.fromstring(archive.read("Doc_0/Document.xml").decode())
    box = document.find(".//ofd:PageArea/ofd:PhysicalBox", NS)
    width_mm, height_mm = (float(v) for v in box.text.split()[2:4])
    width = int(width_mm * SCALE)
    height = int(height_mm * SCALE)

    doc_res = None
    if "Doc_0/DocumentRes.xml" in archive.namelist():
        doc_res = archive.read("Doc_0/DocumentRes.xml").decode()

    image = Image.new("RGB", (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(image, "RGBA")

    content_path = f"Doc_0/Pages/Page_{page_index}/Content.xml"
    page = ET.fromstring(archive.read(content_path).decode())

    font_cache = {}

    def font_for(size_px):
        if size_px not in font_cache:
            font_cache[size_px] = load_font(archive, doc_res, size_px)
        return font_cache[size_px]

    # Images first, so text and rules sit on top.
    for obj in page.findall(".//ofd:ImageObject", NS):
        boundary = [float(v) for v in obj.get("Boundary").split()]
        resource = obj.get("ResourceID")
        # Find the image file whose id matches.
        if doc_res is None:
            continue
        for node in ET.fromstring(doc_res).findall(".//ofd:Image", NS):
            if node.get("ID") != resource:
                continue
            file_node = node.find("ofd:ImageFile", NS)
            if file_node is None:
                continue
            path = f"Doc_0/Res/{file_node.text.strip()}"
            if path not in archive.namelist():
                continue
            import io

            raster = Image.open(io.BytesIO(archive.read(path))).convert("RGBA")
            target = (
                int(boundary[2] * SCALE),
                int(boundary[3] * SCALE),
            )
            raster = raster.resize(target)
            image.paste(
                raster,
                (int(boundary[0] * SCALE), int(boundary[1] * SCALE)),
                raster,
            )

    for obj in page.findall(".//ofd:PathObject", NS):
        boundary = [float(v) for v in obj.get("Boundary").split()]
        stroke = colour(obj.find("ofd:StrokeColor", NS))
        fill = colour(obj.find("ofd:FillColor", NS))
        width_px = max(1, int(float(obj.get("LineWidth", "0.2")) * SCALE))
        data_node = obj.find("ofd:AbbreviatedData", NS)
        if data_node is None:
            continue
        polylines = parse_path(data_node.text or "", boundary[0], boundary[1])
        if obj.get("Fill") == "true" and fill and polylines:
            points = [(x * SCALE, y * SCALE) for x, y in polylines[0]]
            if len(points) >= 3:
                draw.polygon(points, fill=fill + (255,))
        if obj.get("Stroke") == "true" and stroke:
            for line in polylines:
                points = [(x * SCALE, y * SCALE) for x, y in line]
                if len(points) >= 2:
                    draw.line(points, fill=stroke + (255,), width=width_px)

    for obj in page.findall(".//ofd:TextObject", NS):
        boundary = [float(v) for v in obj.get("Boundary").split()]
        size = float(obj.get("Size", "4"))
        fill = colour(obj.find("ofd:FillColor", NS)) or (0, 0, 0)
        code = obj.find("ofd:TextCode", NS)
        if code is None or not code.text:
            continue
        offset_x = float(code.get("X", "0"))
        offset_y = float(code.get("Y", "0"))
        # Baseline sits above the bottom edge of the boundary box.
        baseline_y = boundary[1] + boundary[3] - offset_y
        draw.text(
            ((boundary[0] + offset_x) * SCALE, baseline_y * SCALE),
            code.text,
            font=font_for(max(8, int(size * SCALE))),
            fill=fill + (255,),
            anchor="ls",
        )

    image.save(png_path)
    print(f"wrote {png_path} ({width}x{height} px, page {page_index})")


if __name__ == "__main__":
    main()
