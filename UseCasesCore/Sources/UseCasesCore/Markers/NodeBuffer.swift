/// node's `Buffer.from(text, encoding)` decoders, which are lenient in ways
/// Foundation's are not, and a signature or key read through them must decode
/// to the same bytes.
enum NodeBuffer {
  /// `Buffer.from(text, "base64")`: both the standard and URL-safe alphabets,
  /// every other character skipped, and decoding stopped at the first `=`.
  /// node reads each UTF-16 code unit by its LOW byte, so U+0141 decodes as
  /// `A` and a high surrogate D83D stops decoding as `=`.
  static func base64Decode(_ text: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var accumulator: UInt32 = 0
    var pending = 0
    for unit in text.utf16.map(lowByte) {
      if unit == 0x3D {
        break
      }
      guard let sextet = sextet(unit) else {
        continue
      }
      accumulator = accumulator << 6 | UInt32(sextet)
      pending += 1
      if pending == 4 {
        bytes.append(UInt8(accumulator >> 16 & 0xFF))
        bytes.append(UInt8(accumulator >> 8 & 0xFF))
        bytes.append(UInt8(accumulator & 0xFF))
        accumulator = 0
        pending = 0
      }
    }
    switch pending {
    case 2:
      bytes.append(UInt8(accumulator >> 4 & 0xFF))
    case 3:
      bytes.append(UInt8(accumulator >> 10 & 0xFF))
      bytes.append(UInt8(accumulator >> 2 & 0xFF))
    default:
      break
    }
    return bytes
  }

  /// `Buffer.from(text, "hex")`: pairs of hex digits, stopping at the first
  /// pair that is not one; an odd final digit is dropped. Code units are read
  /// by their low byte, as for base64.
  static func hexDecode(_ text: String) -> [UInt8] {
    let units = text.utf16.map(lowByte)
    var bytes: [UInt8] = []
    var index = 0
    while index + 1 < units.count {
      guard let high = nibble(units[index]), let low = nibble(units[index + 1]) else {
        break
      }
      bytes.append(high << 4 | low)
      index += 2
    }
    return bytes
  }

  static func hexadecimal(_ bytes: some Sequence<UInt8>) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var text: [UInt8] = []
    for byte in bytes {
      text.append(digits[Int(byte >> 4)])
      text.append(digits[Int(byte & 0x0F)])
    }
    return String(String.UnicodeScalarView(text.map { byte in
      Unicode.Scalar(byte)
    }))
  }

  private static func lowByte(_ unit: UInt16) -> UInt16 {
    unit & 0xFF
  }

  private static func sextet(_ unit: UInt16) -> UInt8? {
    switch unit {
    case 0x41 ... 0x5A: UInt8(unit - 0x41)
    case 0x61 ... 0x7A: UInt8(unit - 0x61 + 26)
    case 0x30 ... 0x39: UInt8(unit - 0x30 + 52)
    case 0x2B, CodeUnits.hyphenMinus: 62
    case CodeUnits.solidus, CodeUnits.lowLine: 63
    default: nil
    }
  }

  private static func nibble(_ unit: UInt16) -> UInt8? {
    switch unit {
    case 0x30 ... 0x39: UInt8(unit - 0x30)
    case 0x61 ... 0x66: UInt8(unit - 0x61 + 10)
    case 0x41 ... 0x46: UInt8(unit - 0x41 + 10)
    default: nil
    }
  }
}
