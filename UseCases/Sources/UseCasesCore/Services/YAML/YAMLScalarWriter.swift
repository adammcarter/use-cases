/// Quotes by the reader's rules, reversed: a text stays plain only when the reader's own typing
/// gives it back as that text, in both YAML versions, and it cannot be mistaken for structure
/// or for the start of a comment. Beyond the reader's rules, text that other YAML readers type
/// as something else is quoted too: any text without a space that starts like a number (`0X1F`,
/// `1e3_`, `2001-1-1`, `._`). Everything else is written in double
/// quotes, which can say anything.
struct YAMLScalarWriter: YAMLScalarWriting {
  private static let indicators: Set<Unicode.Scalar> = [
    "-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`",
  ]

  /// What would be read as structure in a list or mapping on one line. `?` is not structure to
  /// libyaml, but PyYAML, Psych and go-yaml refuse it there, and an accepted file must be read
  /// one way (chapter 09 §14).
  private static let flowStructure: Set<Unicode.Scalar> = [",", "[", "]", "{", "}", ":", "?"]

  private let typer: any PlainScalarTyping

  init(typer: any PlainScalarTyping = PlainScalarTyper()) {
    self.typer = typer
  }

  func text(
    of string: String,
    in context: YAMLScalarContext,
  ) -> String {
    isPlain(
      string,
      in: context,
    ) ? string : quoted(string)
  }

  private func isPlain(
    _ string: String,
    in context: YAMLScalarContext,
  ) -> Bool {
    let scalars = Array(string.unicodeScalars)

    guard
      Self.isSafeToLeaveBare(
        scalars,
        in: context,
      ),
      !Self.otherReadersType(scalars: scalars)
    else {
      return false
    }

    return typer.type(of: string) == .value(.string(string))
  }

  private static func isSafeToLeaveBare(
    _ scalars: [Unicode.Scalar],
    in context: YAMLScalarContext,
  ) -> Bool {
    guard
      let first = scalars.first,
      let last = scalars.last,
      first != " ",
      last != " ",
      last != ":",
      !indicators.contains(first),
      scalars.allSatisfy(\.isYAMLPrintable),
      !startsLikeDocumentMarker(scalars)
    else {
      return false
    }

    for (index, scalar) in scalars.enumerated() {
      if context == .flow, flowStructure.contains(scalar) {
        return false
      }

      guard index > 0 else {
        continue
      }

      let before = scalars[index - 1]

      // `: ` would end a key, and ` #` would start a comment.
      if scalar == " ", before == ":" {
        return false
      }

      if scalar == "#", before == " " {
        return false
      }
    }

    return true
  }

  /// Whether a reader other than ours may type the text as something besides text.
  private static func otherReadersType(scalars: [Unicode.Scalar]) -> Bool {
    !scalars.contains(" ") && startsLikeNumber(scalars)
  }

  /// Whether the text begins as a number does in some YAML reader: an optional sign, an optional
  /// dot, then a digit, or after a dot an underscore too (`._`, `.__`).
  private static func startsLikeNumber(_ scalars: [Unicode.Scalar]) -> Bool {
    var rest = scalars[...]

    if rest.first == "+" || rest.first == "-" {
      rest = rest.dropFirst()
    }

    if rest.first == "." {
      rest = rest.dropFirst()

      return rest.first.map { scalar in
        scalar == "_" || isDigit(scalar)
      } ?? false
    }

    return rest.first.map(isDigit) ?? false
  }

  private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    ("0" ... "9").contains(scalar)
  }

  private static func startsLikeDocumentMarker(_ scalars: [Unicode.Scalar]) -> Bool {
    scalars.starts(with: ["-", "-", "-"]) || scalars.starts(with: [".", ".", "."])
  }

  private func quoted(_ string: String) -> String {
    var text = "\""

    for scalar in string.unicodeScalars {
      text += Self.escaped(scalar)
    }

    return text + "\""
  }

  private static let namedEscapes: [Unicode.Scalar: String] = [
    "\"": "\\\"",
    "\\": "\\\\",
    "\u{0}": "\\0",
    "\u{7}": "\\a",
    "\u{8}": "\\b",
    "\t": "\\t",
    "\n": "\\n",
    "\u{B}": "\\v",
    "\u{C}": "\\f",
    "\r": "\\r",
    "\u{1B}": "\\e",
    "\u{85}": "\\N",
    "\u{2028}": "\\L",
    "\u{2029}": "\\P",
  ]

  private static func escaped(_ scalar: Unicode.Scalar) -> String {
    if let named = namedEscapes[scalar] {
      return named
    }

    guard scalar.isYAMLPrintable else {
      return hexadecimal(scalar)
    }

    return String(scalar)
  }

  /// `\xNN`, `\uNNNN` or `\UNNNNNNNN`: the shortest escape that holds the scalar.
  private static func hexadecimal(_ scalar: Unicode.Scalar) -> String {
    let digits = String(scalar.value, radix: 16, uppercase: true)

    switch scalar.value {
    case ...0xFF:
      return "\\x" + padded(digits, to: 2)
    case ...0xFFFF:
      return "\\u" + padded(digits, to: 4)
    default:
      return "\\U" + padded(digits, to: 8)
    }
  }

  private static func padded(
    _ digits: String,
    to width: Int,
  ) -> String {
    String(repeating: "0", count: width - digits.count) + digits
  }
}
