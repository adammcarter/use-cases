/// A schema `pattern`, written in ECMA-262 syntax and run with Swift Regex, for the constructs
/// the bundled schemas use and no others.
///
/// Those constructs are literals, `^`, `$` and `.`, character classes, groups `(?:`, `(?!` and
/// `(?=`, quantifiers, `|`, escaped punctuation, `\n`, `\r`, `\t`, `\s` and `\uHHHH`. For them the
/// match is read one Unicode scalar at a time, `^` and `$` match only at the ends of the text,
/// and `.` stops at the four line terminators ECMA-262 names (`\n`, `\r`, U+2028, U+2029) where
/// Swift Regex's own `.` also stops at U+000B, U+000C and U+0085. `\s` is written out as the
/// ECMA-262 set of white space and line terminators, which is not Swift Regex's: that has U+0085
/// and not U+FEFF.
///
/// Syntax outside that set, whose meaning differs between ECMA-262 and Swift Regex (`\d`, `\w`,
/// `\b`, `\p{`, `(?i)`, `\z`, nested classes and the like), is reported by
/// ``unsupportedSyntax`` and gets no regex, so a future schema cannot silently be given Swift's
/// meaning.
struct SchemaPattern: Equatable, Sendable {
  let source: String

  /// The pattern ready to search with, or nil when it uses unsupported syntax or is not a
  /// regular expression.
  func makeRegex() -> Regex<AnyRegexOutput>? {
    guard unsupportedSyntax == nil, let regex = try? Regex(swiftSource) else {
      return nil
    }

    return regex.matchingSemantics(.unicodeScalar)
  }

  /// The first piece of syntax outside what this type reads, or nil when there is none.
  var unsupportedSyntax: String? {
    let scalars = Array(source.unicodeScalars)
    var position = 0
    var isInsideClass = false

    while position < scalars.count {
      let scalar = scalars[position]

      if scalar == "\\" {
        if let problem = Self.unsupportedEscape(
          scalars,
          at: position,
        ) {
          return problem
        }
        position += Self.isUnicodeEscape(
          scalars,
          at: position,
        ) ? 6 : 2
        continue
      }

      if let problem = Self.unsupportedPunctuation(
        scalars,
        at: position,
        isInsideClass: isInsideClass,
      ) {
        return problem
      }
      if scalar == "[", !isInsideClass {
        isInsideClass = true
      } else if scalar == "]" {
        isInsideClass = false
      }
      position += 1
    }

    return nil
  }

  /// The pattern in Swift Regex syntax: `.` outside a character class becomes the ECMA-262 set.
  var swiftSource: String {
    var translated = ""
    var isInsideClass = false
    var isEscaped = false

    for character in source.unicodeScalars {
      if isEscaped {
        isEscaped = false
        if character == "s" {
          translated.unicodeScalars.removeLast()
          translated += isInsideClass ? Self.whiteSpace : "[" + Self.whiteSpace + "]"
        } else {
          translated.unicodeScalars.append(character)
        }
        continue
      }

      switch character {
      case "\\":
        isEscaped = true
        translated.unicodeScalars.append(character)
      case "[" where !isInsideClass:
        isInsideClass = true
        translated.unicodeScalars.append(character)
      case "]" where isInsideClass:
        isInsideClass = false
        translated.unicodeScalars.append(character)
      case "." where !isInsideClass:
        translated += Self.anyCharacterExceptLineTerminators
      default:
        translated.unicodeScalars.append(character)
      }
    }

    return translated
  }

  /// What ECMA-262 `\s` matches, as the inside of a character class. U+2000 to U+200A are
  /// listed one by one: Swift Regex refuses a range whose ends are white space.
  private static let whiteSpace =
    "\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u00A0\\u1680"
      + "\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200A"
      + "\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"

  private static let anyCharacterExceptLineTerminators = "[^\\n\\r\\u2028\\u2029]"

  private static let setOperators: Set<Unicode.Scalar> = ["&", "-", "~"]

  /// An escape other than punctuation, `\n`, `\r`, `\t`, `\s` and `\u` with four hex digits.
  private static func unsupportedEscape(
    _ scalars: [Unicode.Scalar],
    at position: Int,
  ) -> String? {
    guard position + 1 < scalars.count else {
      return "\\"
    }

    let next = scalars[position + 1]
    guard next.isASCII, next.properties.isAlphabetic || ("0" ... "9").contains(next) else {
      return nil
    }
    if ["n", "r", "t", "s"].contains(next) || isUnicodeEscape(
      scalars,
      at: position,
    ) {
      return nil
    }

    return "\\" + String(next)
  }

  private static func isUnicodeEscape(
    _ scalars: [Unicode.Scalar],
    at position: Int,
  ) -> Bool {
    guard position + 5 < scalars.count, scalars[position + 1] == "u" else {
      return false
    }

    return scalars[(position + 2) ... (position + 5)].allSatisfy {
      $0.isASCII && $0.properties.isASCIIHexDigit
    }
  }

  /// Group kinds and character class forms that Swift Regex reads differently.
  private static func unsupportedPunctuation(
    _ scalars: [Unicode.Scalar],
    at position: Int,
    isInsideClass: Bool,
  ) -> String? {
    let scalar = scalars[position]
    let following = position + 1 < scalars.count ? scalars[position + 1] : nil

    if isInsideClass {
      if scalar == "[" {
        return "[ inside a character class"
      }
      if setOperators.contains(scalar), following == scalar {
        return String(scalar) + String(scalar) + " inside a character class"
      }

      return nil
    }
    guard scalar == "(", following == "?" else {
      return nil
    }

    let kind = position + 2 < scalars.count ? scalars[position + 2] : nil
    if let kind, [":", "!", "="].contains(kind) {
      return nil
    }

    var description = "(?"
    if let kind {
      description.unicodeScalars.append(kind)
    }

    return description
  }
}
