/// One piece of an id: lowercase `a-z`, `0-9` and `-`, never beginning or ending with `-`,
/// never empty (chapter 05).
struct IdentifierSegment: Hashable, Sendable, CustomStringConvertible {
  let text: String

  /// Reads a segment, refusing anything off the grammar, a trailing line break included.
  init(validating text: String) throws(IdentityError) {
    let scalars = Array(text.unicodeScalars)

    guard let first = scalars.first, let last = scalars.last else {
      throw .empty
    }

    for scalar in scalars where !Self.isAllowed(scalar) {
      throw .invalidCharacter(scalar, within: text)
    }

    if first == "-" {
      throw .leadingHyphen(within: text)
    }

    if last == "-" {
      throw .trailingHyphen(within: text)
    }

    self.text = text
  }

  var description: String {
    text
  }

  private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x61 ... 0x7A, 0x30 ... 0x39, 0x2D:
      true
    default:
      false
    }
  }
}
