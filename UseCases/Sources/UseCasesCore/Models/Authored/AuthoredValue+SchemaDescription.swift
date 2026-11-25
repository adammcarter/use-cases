extension AuthoredValue {
  /// How a failure message shows this value: text in single quotes, a long value cut short.
  var schemaDescription: String {
    let full = fullSchemaDescription
    guard full.unicodeScalars.count > Self.descriptionLimit else {
      return full
    }

    return String(full.unicodeScalars.prefix(Self.descriptionLimit - 3)) + "..."
  }

  private static let descriptionLimit = 80

  private var fullSchemaDescription: String {
    switch self {
    case let .string(text):
      Self.quote(text)
    case let .integer(integer):
      String(integer)
    case let .number(number):
      String(number)
    case let .boolean(flag):
      flag ? "true" : "false"
    case .null:
      "null"
    case let .array(elements):
      "[" + elements.map(\.fullSchemaDescription).joined(separator: ", ") + "]"
    case let .object(members):
      Self.describe(members: members)
    }
  }

  private static func describe(members: [AuthoredMember]) -> String {
    var fragments: [String] = []
    for member in members {
      fragments.append(quote(member.key) + ": " + member.value.fullSchemaDescription)
    }

    return leftBrace + fragments.joined(separator: ", ") + rightBrace
  }

  private static let leftBrace = "{"
  private static let rightBrace = "}"

  /// Text in single quotes, with a line break or any other control character spelled out.
  static func quote(_ text: String) -> String {
    var quoted = "'"
    for scalar in text.unicodeScalars {
      quoted += escaped(scalar)
    }

    return quoted + "'"
  }

  private static func escaped(_ scalar: Unicode.Scalar) -> String {
    switch scalar {
    case "\\": "\\\\"
    case "'": "\\'"
    case "\n": "\\n"
    case "\r": "\\r"
    case "\t": "\\t"
    case "\u{0}" ... "\u{1F}", "\u{7F}": unicodeEscape(scalar)
    default: String(scalar)
    }
  }

  /// `\u` and four hex digits, as JSON writes a control character.
  private static func unicodeEscape(_ scalar: Unicode.Scalar) -> String {
    let digits = String(scalar.value, radix: 16)

    return "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
  }
}
