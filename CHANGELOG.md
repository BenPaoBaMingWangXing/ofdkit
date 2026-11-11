# Changelog

All notable changes to ofdkit are recorded here. Versions follow
[Semantic Versioning](https://semver.org/).

## 0.7.0

- **Renumbering font subset.** Kept glyphs are packed into ids `0..n-1`, and
  `loca`, `hmtx`, `maxp`, `cmap` and composite component indices are rewritten
  to match. SimHei drops from 134 KB (sparse subset) to 18 KB.
- **Cross-page tables.** `table_across_pages` adds pages as needed and repeats
  the header row on every continuation page.
- Fixed left side bearing lookup for glyphs past `numberOfHMetrics` — CJK fonts
  keep most bearings in a trailing array, and reading the wrong slot shifted
  every Chinese glyph horizontally.

## 0.6.0

- **Document outline.** `add_outline(title, page, level)` writes a bookmark tree
  into `Document.xml`; the verifier resolves every destination against real
  page ids.

## 0.5.0

- **Tables.** `TableStyle` + `Page::table()` draw a grid with a filled header,
  per-column widths, and ellipsis truncation for cells that do not fit.
- **Alignment.** `Page::text_aligned()` for left / centre / right.
- **Preview renderer.** `scripts/preview_ofd.py` turns a generated package into
  a PNG so layout can be checked without an OFD reader.

## 0.4.0

- **Images.** PNG and JPEG are packaged as-is into `DocumentRes.xml` and placed
  with `Page::image()`; the writer sniffs magic bytes and never decodes pixels.

## 0.3.0

- **Real glyph metrics.** `measure_text` reads `hmtx` advance widths, matching
  FreeType exactly at the same size.
- **Automatic wrapping.** `Page::paragraph()` breaks text to a width, honours
  explicit newlines, and never starts a line with a space.

## 0.2.0

- **TrueType subsetting and embedding.** `embed_font_for_text()` parses the
  font, takes the character set of the text, closes over composite glyphs and
  registers the subset under `PublicRes.xml`.
- Big-endian writers added for the sfnt side; ZIP stays little-endian.
- Fixed the verifier treating `FontFile` as an attribute rather than element
  text, which had made the font checks silently pass.

## 0.1.1

- Emit explicit directory records in the ZIP (`Doc_0/`, `Doc_0/Pages/`, ...).
- Order `CommonData` children as `PageArea` → `PublicRes` → `MaxUnitID` and drop
  the redundant per-page `Area`.
- `MaxUnitID` now covers page object ids, which are allocated in blocks.

## 0.1.0

- First release: OFD package writer (ZIP + `OFD.xml` + `Document.xml` +
  per-page `Content.xml`), text and path objects, multi-page documents,
  structural verifier, and a CLI with `demo` / `verify` / `info`.
