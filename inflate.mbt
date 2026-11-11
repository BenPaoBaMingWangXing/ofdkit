///|
/// DEFLATE decoding for the verifier.
///
/// This reader covers what this project writes (stored and fixed-Huffman
/// blocks) plus what Python's `zipfile` writes for small entries. Dynamic
/// Huffman blocks are rejected on purpose: the verifier's job is to read back
/// our own output, and pretending to be a general inflater would add a code
/// table builder that nothing exercises.

///|
/// LSB-first bit reader with a small lookahead.
pub struct BitReader {
  data : Bytes
  mut pos : Int32
  mut bit : Int32
}

///|
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, pos: 0, bit: 0, }
}

///|
fn BitReader::read_bit(self : BitReader) -> Int32 {
  if self.pos >= self.data.length() {
    return 0
  }
  let value = (self.data[self.pos].to_uint() >> self.bit) & 1U
  self.bit = self.bit + 1
  if self.bit == 8 {
    self.bit = 0
    self.pos = self.pos + 1
  }
  value.reinterpret_as_int()
}

///|
fn BitReader::read_bits(self : BitReader, n : Int32) -> Int32 {
  let mut value = 0
  for i in 0..<n {
    if self.read_bit() != 0 {
      value = value | (1 << i)
    }
  }
  value
}

///|
/// Peek `n` bits without consuming them.
fn BitReader::peek_bits(self : BitReader, n : Int32) -> Int32 {
  let saved_pos = self.pos
  let saved_bit = self.bit
  let value = self.read_bits(n)
  self.pos = saved_pos
  self.bit = saved_bit
  value
}

///|
fn BitReader::consume(self : BitReader, n : Int32) -> Unit {
  for _ in 0..<n {
    ignore(self.read_bit())
  }
}

///|
fn reverse_bits(code : UInt32, len : Int32) -> Int32 {
  let mut out = 0
  for i in 0..<len {
    if ((code >> i) & 1U) == 1U {
      out = out | (1 << (len - 1 - i))
    }
  }
  out
}

///|
/// Decode table for the fixed literal/length alphabet, indexed by the next nine
/// bits of the stream. Each entry is (symbol, code length).
fn fixed_decode_table() -> Array[(Int32, Int32)] {
  let table : Array[(Int32, Int32)] = Array::make(512, (0, 0))
  for symbol in 0..<288 {
    let (code, len) = fixed_literal_code(symbol)
    let reversed = reverse_bits(code, len)
    let step = 1 << len
    let mut index = reversed
    while index < 512 {
      table[index] = (symbol, len)
      index = index + step
    }
  }
  table
}

///|
let fixed_table : Array[(Int32, Int32)] = fixed_decode_table()

///|
fn decode_symbol(reader : BitReader) -> Int32 {
  let peeked = reader.peek_bits(9)
  let (symbol, len) = fixed_table[peeked]
  reader.consume(len)
  symbol
}

///|
fn decode_length(reader : BitReader, symbol : Int32) -> Int32 {
  if symbol <= 264 {
    3 + (symbol - 257)
  } else if symbol <= 268 {
    11 + (symbol - 265) * 2 + reader.read_bits(1)
  } else if symbol <= 272 {
    19 + (symbol - 269) * 4 + reader.read_bits(2)
  } else if symbol <= 276 {
    35 + (symbol - 273) * 8 + reader.read_bits(3)
  } else if symbol <= 280 {
    67 + (symbol - 277) * 16 + reader.read_bits(4)
  } else if symbol <= 284 {
    131 + (symbol - 281) * 32 + reader.read_bits(5)
  } else {
    258
  }
}

///|
/// Read a Huffman code of `n` bits. Huffman codes arrive most-significant bit
/// first while everything else in the stream is least-significant bit first, so
/// the raw value has to be reversed.
fn BitReader::read_huffman(self : BitReader, n : Int32) -> Int32 {
  reverse_bits(self.read_bits(n).reinterpret_as_uint(), n)
}

///|
/// First distance and extra-bit count for each distance code.
fn distance_base(code : Int32) -> (Int32, Int32) {
  if code >= 0 && code < distance_table.length() {
    distance_table[code]
  } else {
    (1, 0)
  }
}

///|
/// Inflate a raw DEFLATE stream. Returns an error string for the block types
/// this reader does not implement.
pub fn inflate_raw(data : Bytes) -> Result[Bytes, String] {
  let reader = BitReader::new(data)
  let out = ByteBuf::new()
  let mut last = false
  while !last {
    last = reader.read_bit() != 0
    let block_type = reader.read_bits(2)
    if block_type == 0 {
      // Stored block: align to a byte boundary, then copy LEN bytes.
      if reader.bit != 0 {
        reader.bit = 0
        reader.pos = reader.pos + 1
      }
      if reader.pos + 4 > data.length() {
        return Err("deflate: truncated stored block header")
      }
      let len = data[reader.pos].to_uint() |
        (data[reader.pos + 1].to_uint() << 8)
      reader.pos = reader.pos + 4
      let count = len.reinterpret_as_int()
      if reader.pos + count > data.length() {
        return Err("deflate: truncated stored block")
      }
      for i in 0..<count {
        out.write_byte(data[reader.pos + i])
      }
      reader.pos = reader.pos + count
    } else if block_type == 1 {
      // Fixed Huffman.
      let mut done = false
      while !done {
        let symbol = decode_symbol(reader)
        if symbol < 256 {
          out.write_byte(symbol.to_byte())
        } else if symbol == 256 {
          done = true
        } else if symbol <= 285 {
          let length = decode_length(reader, symbol)
          let dist_code = reader.read_huffman(5)
          let (base, extra) = distance_base(dist_code)
          let distance = base + reader.read_bits(extra)
          let start = out.length() - distance
          if start < 0 {
            return Err("deflate: distance points before the output start")
          }
          for i in 0..<length {
            out.write_byte(out.byte_at(start + i))
          }
        } else {
          return Err("deflate: invalid length symbol \{symbol}")
        }
      }
    } else {
      return Err(
        "deflate: block type \{block_type} is not supported by this reader",
      )
    }
  }
  Ok(out.to_bytes())
}
