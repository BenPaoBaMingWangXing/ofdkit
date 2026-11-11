// ofdkit — OFD (GB/T 33190-2016) document writer and structural verifier.

name = "BenPaoBaMingWangXing/ofdkit"

version = "0.5.0"

readme = "README.mbt.md"

repository = "https://github.com/BenPaoBaMingWangXing/ofdkit"

license = "Apache-2.0"

keywords = [
  "ofd",
  "gb-t-33190",
  "document",
  "fixed-layout",
  "writer",
  "chinese",
]

preferred_target = "wasm"

description = "Pure MoonBit writer and structural verifier for OFD fixed-layout documents (GB/T 33190-2016): multi-page packages, text and path objects, TrueType font subsetting and embedding, real glyph metrics for text layout, PNG/JPEG image resources, tables and alignment, and a self-checking CLI."

import {
  "moonbitlang/x@0.5.5",
}
