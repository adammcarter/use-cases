/// Text written the way a UTF-16 or UTF-32 file holds it, byte-order mark first.
enum WideEncoding {
  static func utf16(
    _ text: String,
    bigEndian: Bool,
  ) -> [UInt8] {
    var bytes: [UInt8] = bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]

    for unit in text.utf16 {
      let low = UInt8(unit & 0xFF)
      let high = UInt8(unit >> 8)

      bytes += bigEndian ? [high, low] : [low, high]
    }

    return bytes
  }

  static func utf32(
    _ text: String,
    bigEndian: Bool,
  ) -> [UInt8] {
    var bytes: [UInt8] = bigEndian ? [0x00, 0x00, 0xFE, 0xFF] : [0xFF, 0xFE, 0x00, 0x00]

    for scalar in text.unicodeScalars {
      let value = scalar.value
      let little = [0, 8, 16, 24].map { shift in
        UInt8((value >> UInt32(shift)) & 0xFF)
      }

      bytes += bigEndian ? little.reversed() : little
    }

    return bytes
  }
}
