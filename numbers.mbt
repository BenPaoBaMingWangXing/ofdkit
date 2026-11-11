///|
/// Formatting helpers for the numbers that end up in OFD attributes.
///
/// OFD coordinates are millimetres written as decimal numbers. We round to
/// 1/1000 mm, which is far below any device resolution and keeps the output
/// stable so generated packages diff cleanly.

///|
pub fn fmt_mm(value : Double) -> String {
  let rounded = (value * 1000.0).round() / 1000.0
  rounded.to_string()
}

///|
/// Three decimal places are enough for geometry; this trims the trailing noise
/// that `Double::to_string` can leave behind.
pub fn fmt_hex(value : UInt32) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  ]
  let out = StringBuilder()
  for i in 0..<8 {
    let shift = (7 - i) * 4
    let nibble = ((value >> shift) & 0xFU).reinterpret_as_int()
    out.write_char(digits[nibble])
  }
  out.to_string()
}

///|
/// Parse a decimal number. Returns `None` for anything the caller would regret
/// silently treating as zero.
pub fn parse_double(text : String) -> Double? {
  let trimmed = text.trim()
  if trimmed == "" {
    return None
  }
  let mut value = 0.0
  let mut scale = 1.0
  let mut seen_dot = false
  let mut seen_digit = false
  for ch in trimmed {
    if ch == '.' {
      if seen_dot {
        return None
      }
      seen_dot = true
    } else if ch >= '0' && ch <= '9' {
      seen_digit = true
      let digit = (ch.to_uint().reinterpret_as_int() - 48).to_double()
      if seen_dot {
        scale = scale / 10.0
        value = value + digit * scale
      } else {
        value = value * 10.0 + digit
      }
    } else {
      return None
    }
  }
  if !seen_digit {
    return None
  }
  Some(value)
}
