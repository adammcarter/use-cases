/// UTF-16 code-unit arithmetic, because the TypeScript being ported indexes,
/// slices and compares JavaScript strings — which are UTF-16 code units.
///
/// Swift's `String` compares by canonical equivalence and indexes by grapheme,
/// so `hasPrefix`, `==` and `count` all give different answers from JavaScript
/// for combining marks and astral characters. The marker code therefore works
/// on `[UInt16]` wherever the TypeScript's answer depends on it.
enum CodeUnits {
  static let tab: UInt16 = 0x09
  static let lineFeed: UInt16 = 0x0A
  static let carriageReturn: UInt16 = 0x0D
  static let space: UInt16 = 0x20
  static let quotationMark: UInt16 = 0x22
  static let numberSign: UInt16 = 0x23
  static let leftParenthesis: UInt16 = 0x28
  static let rightParenthesis: UInt16 = 0x29
  static let asterisk: UInt16 = 0x2A
  static let fullStop: UInt16 = 0x2E
  static let solidus: UInt16 = 0x2F
  static let colon: UInt16 = 0x3A
  static let commercialAt: UInt16 = 0x40
  static let leftSquareBracket: UInt16 = 0x5B
  static let reverseSolidus: UInt16 = 0x5C
  static let rightSquareBracket: UInt16 = 0x5D
  static let lowLine: UInt16 = 0x5F
  static let leftCurlyBracket: UInt16 = 0x7B
  static let rightCurlyBracket: UInt16 = 0x7D
  static let hyphenMinus: UInt16 = 0x2D

  /// A string from code units that never split a surrogate pair.
  static func string(_ units: some Collection<UInt16>) -> String {
    String(decoding: units, as: UTF16.self)
  }

  /// JavaScript's `[ \t]`.
  static func isSpaceOrTab(_ unit: UInt16) -> Bool {
    unit == space || unit == tab
  }

  /// JavaScript's `\s`: WhiteSpace plus LineTerminator, per code unit.
  static func isJavaScriptWhitespace(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x09 ... 0x0D, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
         0x3000, 0xFEFF:
      true
    default:
      false
    }
  }

  static func isASCIILetter(_ unit: UInt16) -> Bool {
    (0x41 ... 0x5A).contains(unit) || (0x61 ... 0x7A).contains(unit)
  }

  static func isASCIIDigit(_ unit: UInt16) -> Bool {
    (0x30 ... 0x39).contains(unit)
  }

  static func isLowercaseASCIILetter(_ unit: UInt16) -> Bool {
    (0x61 ... 0x7A).contains(unit)
  }

  /// JavaScript's `[A-Za-z_]`.
  static func isWordStart(_ unit: UInt16) -> Bool {
    isASCIILetter(unit) || unit == lowLine
  }

  /// JavaScript's `[A-Za-z0-9_]`, which is also what `\b` means without the `u` flag.
  static func isWordCharacter(_ unit: UInt16) -> Bool {
    isWordStart(unit) || isASCIIDigit(unit)
  }

  /// The number of leading `[ \t]` units at or after `start`.
  static func spaceOrTabRun(
    _ units: [UInt16],
    from start: Int,
  ) -> Int {
    var index = start
    while index < units.count, isSpaceOrTab(units[index]) {
      index += 1
    }
    return index - start
  }

  /// `units` with trailing `[ \t]` removed.
  static func trimmingTrailingSpaceOrTab(_ units: [UInt16]) -> [UInt16] {
    var end = units.count
    while end > 0, isSpaceOrTab(units[end - 1]) {
      end -= 1
    }
    return Array(units[..<end])
  }

  /// JavaScript's `units.startsWith(prefix, position)` for a non-empty prefix.
  static func hasPrefix(
    _ units: [UInt16],
    _ prefix: [UInt16],
    at position: Int,
  ) -> Bool {
    guard position >= 0, position + prefix.count <= units.count else {
      return false
    }
    return units[position ..< position + prefix.count].elementsEqual(prefix)
  }

  /// True when an ASCII word in `candidates` begins at `position` and a word
  /// boundary follows it — the `(a|b|c)\b` of a JavaScript pattern.
  static func hasWord(
    _ units: [UInt16],
    at position: Int,
    among candidates: [[UInt16]],
  ) -> Bool {
    candidates.contains { candidate in
      hasPrefix(units, candidate, at: position) && isBoundary(units, at: position + candidate.count)
    }
  }

  /// `\b` immediately before `position`, given that `units[position - 1]` is a
  /// word character (true for every keyword this is used after).
  static func isBoundary(
    _ units: [UInt16],
    at position: Int,
  ) -> Bool {
    position >= units.count || !isWordCharacter(units[position])
  }
}
