/// A run id (chapter 12 §8): 32 lowercase hexadecimal digits, an unsigned 128-bit number written
/// at a fixed width, so ordering the text is ordering the number. All zeros is reserved.
struct RunIdentifier: Hashable, Comparable, Sendable, CustomStringConvertible {
  static let length = 32

  let text: String

  /// Reads a run id, refusing anything but 32 lowercase hex digits and the reserved zero.
  init(validating text: String) throws(RunIdentifierError) {
    let scalars = Array(text.unicodeScalars)

    guard scalars.count == Self.length else {
      throw .wrongLength(text)
    }
    guard scalars.allSatisfy(Self.isLowercaseHexDigit) else {
      throw .notLowercaseHex(text)
    }
    guard scalars.contains(where: { $0 != "0" }) else {
      throw .reserved
    }

    self.text = text
  }

  var description: String {
    text
  }

  static func < (
    lhs: RunIdentifier,
    rhs: RunIdentifier,
  ) -> Bool {
    lhs.text.precedesExactly(rhs.text)
  }

  private static func isLowercaseHexDigit(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x30 ... 0x39, 0x61 ... 0x66:
      true
    default:
      false
    }
  }
}
