///|
/// DEFLATE encoding (RFC 1951), fixed Huffman blocks with greedy LZ77.
///
/// OFD packages are mostly XML plus one font subset; both compress well. This
/// is a writer only — the reader side stays `stored`, because the verifier must
/// be able to read back whatever we write without depending on this code.
///
/// Fixed Huffman keeps the implementation small: no code-length trees to build
/// or transmit. The trade-off is a few percent worse ratio than dynamic
/// Huffman, which does not matter at package sizes measured in kilobytes.

///|
/// LSB-first bit writer. DEFLATE packs bits into bytes starting at the least
/// significant bit; Huffman codes themselves are written most-significant bit
/// first, which `write_huffman` handles.
pub struct BitWriter {
  out : ByteBuf
  mut bits : UInt32
  mut count : Int32
}

///|
pub fn BitWriter::new() -> BitWriter {
  { out: ByteBuf::new(), bits: 0U, count: 0, }
}

///|
fn BitWriter::write_bit(self : BitWriter, bit : Bool) -> Unit {
  if bit {
    self.bits = self.bits | (1U << self.count)
  }
  self.count = self.count + 1
  if self.count == 8 {
    self.out.write_byte(self.bits.to_byte())
    self.bits = 0U
    self.count = 0
  }
}

///|
/// Write `n` bits, least significant first. Used for extra bits and block
/// headers, which are defined that way.
fn BitWriter::write_bits(self : BitWriter, value : UInt32, n : Int32) -> Unit {
  for i in 0..<n {
    self.write_bit(((value >> i) & 1U) == 1U)
  }
}

///|
/// Write a Huffman code, most significant bit first.
fn BitWriter::write_huffman(self : BitWriter, code : UInt32, n : Int32) -> Unit {
  let mut i = n - 1
  while i >= 0 {
    self.write_bit(((code >> i) & 1U) == 1U)
    i = i - 1
  }
}

///|
pub fn BitWriter::flush(self : BitWriter) -> Bytes {
  if self.count > 0 {
    self.out.write_byte(self.bits.to_byte())
    self.bits = 0U
    self.count = 0
  }
  self.out.to_bytes()
}

///|
/// Fixed literal/length code for symbol 0..287, per RFC 1951 section 3.2.6.
fn fixed_literal_code(symbol : Int32) -> (UInt32, Int32) {
  if symbol <= 143 {
    (0x30U + symbol.reinterpret_as_uint(), 8)
  } else if symbol <= 255 {
    (0x190U + (symbol - 144).reinterpret_as_uint(), 9)
  } else if symbol <= 279 {
    ((symbol - 256).reinterpret_as_uint(), 7)
  } else {
    (0xC0U + (symbol - 280).reinterpret_as_uint(), 8)
  }
}

///|
/// Map a match length (3..258) to its length code and extra bits.
fn encode_length(length : Int32) -> (Int32, UInt32, Int32) {
  // (base length, code, extra bits) for each bucket.
  if length <= 10 {
    (257 + (length - 3), 0U, 0)
  } else if length <= 18 {
    let bucket = (length - 11) / 2
    (265 + bucket, ((length - 11) % 2).reinterpret_as_uint(), 1)
  } else if length <= 34 {
    let bucket = (length - 19) / 4
    (269 + bucket, ((length - 19) % 4).reinterpret_as_uint(), 2)
  } else if length <= 66 {
    let bucket = (length - 35) / 8
    (273 + bucket, ((length - 35) % 8).reinterpret_as_uint(), 3)
  } else if length <= 130 {
    let bucket = (length - 67) / 16
    (277 + bucket, ((length - 67) % 16).reinterpret_as_uint(), 4)
  } else if length <= 257 {
    let bucket = (length - 131) / 32
    (281 + bucket, ((length - 131) % 32).reinterpret_as_uint(), 5)
  } else {
    (285, 0U, 0)
  }
}

///|
/// Distance code table from RFC 1951 section 3.2.5: entry `i` is (first distance
/// covered by code `i`, extra bits for that code). Codes 0..3 each cover a
/// single distance with no extra bits; from code 4 on the ranges double as the
/// extra-bit count grows every two codes.
let distance_table : Array[(Int32, Int32)] = [
  (1, 0),
  (2, 0),
  (3, 0),
  (4, 0),
  (5, 1),
  (7, 1),
  (9, 2),
  (13, 2),
  (17, 3),
  (25, 3),
  (33, 4),
  (49, 4),
  (65, 5),
  (97, 5),
  (129, 6),
  (193, 6),
  (257, 7),
  (385, 7),
  (513, 8),
  (769, 8),
  (1025, 9),
  (1537, 9),
  (2049, 10),
  (3073, 10),
  (4097, 11),
  (6145, 11),
  (8193, 12),
  (12289, 12),
  (16385, 13),
  (24577, 13),
]

///|
/// Map a match distance (1..32768) to its distance code and extra bits.
fn encode_distance(distance : Int32) -> (Int32, UInt32, Int32) {
  for i in 0..<distance_table.length() {
    let (base, extra) = distance_table[i]
    let span = if extra == 0 { 1 } else { 1 << extra }
    if distance < base + span {
      return (i, (distance - base).reinterpret_as_uint(), extra)
    }
  }
  // Distances above 32768 cannot be expressed; `WINDOW` keeps us far below that.
  (29, 32767U, 13)
}

///|
const HASH_BITS : Int32 = 15

///|
const HASH_SIZE : Int32 = 1 << HASH_BITS

///|
/// Maximum backward distance. 32 KiB is the DEFLATE maximum and matches the
/// window every inflater is required to support.
const WINDOW : Int32 = 32768

///|
const MIN_MATCH : Int32 = 3

///|
const MAX_MATCH : Int32 = 258

///|
/// How many hash-chain candidates to inspect before settling for the best match
/// found so far. Higher means better ratio and slower compression.
const MAX_CHAIN : Int32 = 48

///|
/// Stop searching a chain once a match this long is found; longer matches are
/// rare and cost more time than the handful of bits they save.
const GOOD_MATCH : Int32 = 128

///|
fn hash3(data : Bytes, at : Int32) -> Int32 {
  let a = data[at].to_uint()
  let b = data[at + 1].to_uint()
  let c = data[at + 2].to_uint()
  let h = (a << 10) ^ (b << 5) ^ c
  (h & (HASH_SIZE - 1).reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// Push position `at` onto the hash chain for its three-byte prefix.
fn insert_position(
  data : Bytes,
  at : Int32,
  heads : Array[Int32],
  prev : Array[Int32],
) -> Unit {
  if at + MIN_MATCH <= data.length() {
    let h = hash3(data, at)
    prev[at] = heads[h]
    heads[h] = at
  }
}

///|
/// Longest match for the three-byte prefix at `at`, searching the hash chain
/// backwards within the window. Returns (length, distance) or (0, 0).
fn longest_match(
  data : Bytes,
  at : Int32,
  heads : Array[Int32],
  prev : Array[Int32],
) -> (Int32, Int32) {
  let n = data.length()
  if at + MIN_MATCH > n {
    return (0, 0)
  }
  let limit = if n - at < MAX_MATCH { n - at } else { MAX_MATCH }
  // Start from the shortest match worth encoding so the quick reject below
  // compares the right byte.
  let mut best = MIN_MATCH - 1
  let mut best_dist = 0
  let mut candidate = heads[hash3(data, at)]
  let mut steps = 0
  while candidate >= 0 && steps < MAX_CHAIN && at - candidate <= WINDOW {
    if data[candidate + best] == data[at + best] {
      let mut length = 0
      while length < limit && data[candidate + length] == data[at + length] {
        length = length + 1
      }
      if length > best {
        best = length
        best_dist = at - candidate
        if best >= limit || best >= GOOD_MATCH {
          break
        }
      }
    }
    candidate = prev[candidate]
    steps = steps + 1
  }
  if best_dist == 0 {
    (0, 0)
  } else {
    (best, best_dist)
  }
}

///|
/// Emit one match token: length symbol, length extra bits, distance code,
/// distance extra bits.
fn write_match(writer : BitWriter, length : Int32, distance : Int32) -> Unit {
  let (symbol, extra, extra_bits) = encode_length(length)
  let (code, code_bits) = fixed_literal_code(symbol)
  writer.write_huffman(code, code_bits)
  if extra_bits > 0 {
    writer.write_bits(extra, extra_bits)
  }
  let (dist_code, dist_extra, dist_bits) = encode_distance(distance)
  // The distance code is a fixed-length Huffman code, so like every other
  // Huffman code it goes out most-significant bit first. Only the extra bits
  // after it are plain integers (least significant bit first).
  writer.write_huffman(dist_code.reinterpret_as_uint(), 5)
  if dist_bits > 0 {
    writer.write_bits(dist_extra, dist_bits)
  }
}

///|
/// Compress `data` into a raw DEFLATE stream (no zlib wrapper). The output can
/// be handed to any inflater, including Python's `zlib.decompressobj(-15)`.
///
/// One final fixed-Huffman block, greedy LZ77 with one step of lazy matching:
/// when the next position starts a longer match, the current byte is emitted as
/// a literal instead. That single step is what keeps the ratio near zlib's on
/// XML, where long matches usually start one byte late.
pub fn deflate_raw(data : Bytes) -> Bytes {
  let n = data.length()
  let writer = BitWriter::new()
  writer.write_bit(true) // BFINAL
  writer.write_bits(1U, 2) // BTYPE: fixed Huffman
  let heads : Array[Int32] = Array::make(HASH_SIZE, -1)
  let prev : Array[Int32] = Array::make(n, -1)
  let mut i = 0
  while i < n {
    let (length, distance) = longest_match(data, i, heads, prev)
    insert_position(data, i, heads, prev)
    let (next_length, _) = if i + 1 < n {
      longest_match(data, i + 1, heads, prev)
    } else {
      (0, 0)
    }
    if length >= MIN_MATCH && length >= next_length {
      write_match(writer, length, distance)
      // Register the bytes the match skipped so later matches can reach them.
      let mut k = 1
      while k < length {
        insert_position(data, i + k, heads, prev)
        k = k + 1
      }
      i = i + length
    } else {
      let (code, bits) = fixed_literal_code(data[i].to_int())
      writer.write_huffman(code, bits)
      i = i + 1
    }
  }
  // End of block.
  let (eob_code, eob_bits) = fixed_literal_code(256)
  writer.write_huffman(eob_code, eob_bits)
  writer.flush()
}
