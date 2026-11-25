/// Texts a use case may hold and a YAML writer must get right: ones that read as something
/// other than text, that look like structure or a comment, that hold line breaks and control
/// characters, and long ones.
enum NastyText {
  static let fixed: [String] = [
    "", " ", "x", "Dark mode", "A 5.00 discount is applied to a 3.00 invoice.",
    "No", "on", "yes", "Off", "y", "n", "null", "~", "true", "False",
    "1e3", "0o17", "1:30", "2024-01-01", "2024-01-01 10:00:00", "123", "-5", "+1", "1_000",
    "0x1F", "017", ".inf", "-.inf", ".nan", "1.5", "<<", "=",
    "---", "...", "--- x", "- a", "-", "? a", ": a", "a: b", "a:b", "a:", "# c", "a #b", "a#b",
    "Check medal #4 shows", "[x]", "{x}", "a, b", "a,b", "*a", "&a", "!a", "|", ">", "'a'",
    "\"a\"", "%a", "@a", "`a`", "key: [a, b]",
    " lead", "trail ", "tab\tin", "new\nline", "cr\rlf", "\u{85}", "\u{2028}", "\u{2029}",
    "x\u{FEFF}y", "\u{0}", "\u{7F}", "\u{1B}[0m", "back\\slash", "quote\"in", "it's",
    "Is the total zero?", "x?", "?x", "a ? b",
    "y", "Y", "n", "N", "0X1F", "0B1", "0O17", "+0o7", "1e3_", "09_", "._", ".__", "0o_",
    "2001-1-1", "1st", "3d", "1.2.3", ".gitignore", "+x", "_1", "5 items", "version 1.2",
    "line one\nline two", "a\nb\n", "a\n\n", "a\n\n\n\nb", " lead\nsecond", "\nlead blank",
    "\n\nlead blanks\nx", "trail \nspace", "tab\n\tx", "x\n  \ny", "x\n \n", "a\n\n  \n",
    "# not a comment\n- not a list\n? not a key\n---\n...", "end with space \n", "\n \nx",
    "windows\r\nbreak", "ctrl\u{1}\nx", "nel\u{85}\nx", "ls\u{2028}\nx", "bom\u{FEFF}\nx",
    "tabs only\n\t\t\ny", "multi\nline with: colon\nand \"quotes\" and 'apostrophes'",
    "😀", "e\u{301}", "日本語", "a\u{A0}b", "\u{FFFE}", "\u{10FFFF}",
    String(repeating: "x", count: 500),
    Array(repeating: "word", count: 150).joined(separator: " "),
  ]

  private static let alphabet = Array(" abcXYZ019:#-,[]{}!&*|>'\"%@`\\\t\n.~?<=")

  /// One of the fixed texts, or a short run of the characters YAML treats as something.
  static func text(using generator: inout SeededGenerator) -> String {
    if Bool.random(using: &generator) {
      return fixed.randomElement(using: &generator) ?? ""
    }

    let length = Int.random(
      in: 0 ... 12,
      using: &generator,
    )

    return String((0 ..< length).compactMap { _ in
      alphabet.randomElement(using: &generator)
    })
  }

  /// A fingerprint, or something that looks like a number: digits, or digits with an exponent.
  static func fingerprint(using generator: inout SeededGenerator) -> String {
    let hexadecimal = Array("0123456789abcdef")
    let digits = Array("0123456789")

    switch Int.random(
      in: 0 ..< 5,
      using: &generator,
    ) {
    case 0:
      return String((0 ..< 64).compactMap { _ in
        hexadecimal.randomElement(using: &generator)
      })
    case 1:
      return String((0 ..< 64).compactMap { _ in
        digits.randomElement(using: &generator)
      })
    case 2:
      return "1e" + String((0 ..< 62).compactMap { _ in
        digits.randomElement(using: &generator)
      })
    case 3:
      return String(repeating: "0", count: 64)
    default:
      return "0x" + String((0 ..< 62).compactMap { _ in
        hexadecimal.randomElement(using: &generator)
      })
    }
  }
}
