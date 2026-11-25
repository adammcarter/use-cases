/// A run id as the unsigned 128-bit number it stands for (chapter 12 §8), in two halves because
/// `UInt128` needs a newer system than the package supports.
struct RunNumber: Hashable, Comparable, Sendable {
  /// Bits 64 to 127: the 48 bits of milliseconds since 1970 and the first 16 random bits.
  let high: UInt64

  /// Bits 0 to 63: the rest of the 80 random bits.
  let low: UInt64

  private static let hexDigits = Array("0123456789abcdef".unicodeScalars)

  init(
    high: UInt64,
    low: UInt64,
  ) {
    self.high = high
    self.low = low
  }

  /// The number of a run id, which is 32 lowercase hexadecimal digits.
  init(identifier: RunIdentifier) {
    var high: UInt64 = 0
    var low: UInt64 = 0

    for (index, scalar) in identifier.text.unicodeScalars.enumerated() {
      let digit = UInt64(Self.value(of: scalar))

      if index < 16 {
        high = high << 4 | digit
      } else {
        low = low << 4 | digit
      }
    }

    self.init(
      high: high,
      low: low,
    )
  }

  /// The id a clock reading and 80 random bits make: the time in the top 48 bits (chapter 12 §8).
  ///
  /// - Parameters:
  ///   - milliseconds: Milliseconds since 1970. Only the low 48 bits are kept.
  ///   - randomHigh: The 16 bits of the 80 that sit beside the time.
  ///   - randomLow: The other 64 bits.
  init(
    milliseconds: UInt64,
    randomHigh: UInt16,
    randomLow: UInt64,
  ) {
    self.init(
      high: (milliseconds & 0xFFFF_FFFF_FFFF) << 16 | UInt64(randomHigh),
      low: randomLow,
    )
  }

  /// The next number up, or `nil` when this is the greatest there is.
  var successor: RunNumber? {
    if low < UInt64.max {
      return RunNumber(
        high: high,
        low: low + 1,
      )
    }
    if high < UInt64.max {
      return RunNumber(
        high: high + 1,
        low: 0,
      )
    }

    return nil
  }

  /// The 32 lowercase hexadecimal digits, which are the id.
  var text: String {
    Self.hex(high) + Self.hex(low)
  }

  static func < (
    lhs: RunNumber,
    rhs: RunNumber,
  ) -> Bool {
    if lhs.high != rhs.high {
      return lhs.high < rhs.high
    }

    return lhs.low < rhs.low
  }

  /// The run id of this number.
  func identifier() throws(RunIdentifierError) -> RunIdentifier {
    try RunIdentifier(validating: text)
  }

  private static func value(of scalar: Unicode.Scalar) -> UInt8 {
    switch scalar.value {
    case 0x30 ... 0x39:
      UInt8(scalar.value - 0x30)
    case 0x61 ... 0x66:
      UInt8(scalar.value - 0x61 + 10)
    default:
      0
    }
  }

  private static func hex(_ number: UInt64) -> String {
    var digits = String.UnicodeScalarView()

    for shift in stride(from: 60, through: 0, by: -4) {
      digits.append(hexDigits[Int(number >> UInt64(shift) & 0xF)])
    }

    return String(digits)
  }
}
