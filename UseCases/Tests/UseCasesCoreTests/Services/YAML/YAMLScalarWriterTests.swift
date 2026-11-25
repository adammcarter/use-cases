import Testing
@testable import UseCasesCore

struct YAMLScalarWriterTests {
  private let writer = YAMLScalarWriter()
  private let reader = StrictYAMLReader()

  /// What the strict reader reads a text written as `written` after a key.
  private func readBlock(_ written: String) throws -> AuthoredValue? {
    let value = try reader.read(
      "key: \(written)\n",
      file: "a.yml",
      kind: .useCase,
    )

    guard case let .object(members) = value else {
      return nil
    }

    return members.first?.value
  }

  /// What the strict reader reads a text written as `written` as the item of a list on one line.
  private func readFlow(_ written: String) throws -> AuthoredValue? {
    let value = try reader.read(
      "key: [\(written)]\n",
      file: "a.yml",
      kind: .useCase,
    )

    guard case let .object(members) = value, case let .array(items)? = members.first?.value else {
      return nil
    }

    return items.first
  }

  @Test(arguments: [
    "Dark mode",
    "A 5.00 discount is applied to a 3.00 invoice.",
    "No tax is charged (reverse charge).",
    "it's a user's",
    "a#b",
    "日本語",
    "😀 done",
    "src/invoicing/tax.py",
    "Customers are charged the sum of their lines, less discounts, plus tax.",
    "back\\slash",
  ])
  func `text that reads as itself stays plain`(text: String) {
    #expect(writer.text(of: text, in: .block) == text)
  }

  @Test(arguments: [
    "", " ", " lead", "trail ",
    "No", "on", "yes", "Off", "null", "~", "true", "1e3", "0o17", "1:30", "2024-01-01",
    "123", "-5", "1.5", ".inf", ".nan", "<<", "=",
    "---", "...", "--- x", "- a", "-", "? a", ": a", "a: b", "a:", "# c", "a #b",
    "[x]", "{x}", "*a", "&a", "!a", "|", ">", "'a'", "\"a\"", "%a", "@a", "`a`",
    "tab\tin", "new\nline", "cr\rlf", "\u{85}", "\u{2028}", "\u{FEFF}", "\u{0}", "\u{7F}",
  ])
  func `text that would be read as something else is quoted`(text: String) {
    let written = writer.text(of: text, in: .block)

    #expect(written.hasPrefix("\""))
    #expect(written.hasSuffix("\""))
  }

  @Test(arguments: [
    ("a, b", "a, b", "\"a, b\""),
    ("a,b", "a,b", "\"a,b\""),
    ("a:b", "a:b", "\"a:b\""),
    ("[x]", "\"[x]\"", "\"[x]\""),
    ("a{b}", "a{b}", "\"a{b}\""),
  ])
  func `an item of a list on one line is quoted for the characters that split it`(
    text: String,
    block: String,
    flow: String,
  ) {
    #expect(writer.text(of: text, in: .block) == block)
    #expect(writer.text(of: text, in: .flow) == flow)
  }

  // Mutant: `?` left out of the characters that are structure in a list on one line.
  @Test(arguments: ["Is the total zero?", "x?", "a ? b", "?x"])
  func `a question mark is quoted in a list on one line, where PyYAML and Psych refuse it`(
    text: String,
  ) {
    #expect(writer.text(of: text, in: .flow) == "\"\(text)\"")
  }

  @Test
  func `a question mark inside a text is plain after a key, where every reader allows it`() {
    #expect(writer.text(of: "Is the total zero?", in: .block) == "Is the total zero?")
  }

  // Decided: chapter 09's YAML 1.1 schema reads a lone y or n as text, and PyYAML, ruamel,
  // libyaml and Psych agree, so it stays plain (only go-yaml version 2 differs).
  @Test(arguments: ["y", "Y", "n", "N"])
  func `a lone y or n stays plain, where every reader but go-yaml 2 reads it as text`(
    text: String,
  ) {
    #expect(writer.text(of: text, in: .block) == text)
    #expect(writer.text(of: text, in: .flow) == text)
  }

  @Test(arguments: ["yo", "ny", "y.", "y n", "yes please", "nope"])
  func `other texts that start with y or n stay plain`(text: String) {
    #expect(writer.text(of: text, in: .block) == text)
  }

  // Mutant: the number-like rule left out of `isPlain`.
  @Test(arguments: [
    "0X1F", "0B1", "0O17", "+0o7", "1e3_", "09_", "._", ".__", "0o_", "2001-1-1", "1st", "3d",
    "1.2.3", "12abc", "+5x", ".5x", "+._", "-.5",
  ])
  func `a text without a space that starts like a number is quoted`(text: String) {
    #expect(writer.text(of: text, in: .block) == "\"\(text)\"")
  }

  @Test(arguments: [
    "5 items", "version 1.2", "1 2", ".gitignore", "+x", "_1", "..x", "a1", "x.5", "v2.0.0",
  ])
  func `a text with a space, or that starts otherwise, stays plain`(text: String) {
    #expect(writer.text(of: text, in: .block) == text)
  }

  @Test(arguments: [
    ("say: \"hi\"", "\"say: \\\"hi\\\"\""),
    ("a\\b: c", "\"a\\\\b: c\""),
    ("line\nbreak", "\"line\\nbreak\""),
    ("a\tb", "\"a\\tb\""),
    ("a\rb", "\"a\\rb\""),
    ("a\u{0}b", "\"a\\0b\""),
    ("a\u{7}b", "\"a\\ab\""),
    ("a\u{1B}b", "\"a\\eb\""),
    ("a\u{7F}b", "\"a\\x7Fb\""),
    ("a\u{85}b", "\"a\\Nb\""),
    ("a\u{2028}b", "\"a\\Lb\""),
    ("a\u{2029}b", "\"a\\Pb\""),
    ("\u{FEFF}", "\"\\uFEFF\""),
    ("\u{FFFE}", "\"\\uFFFE\""),
    ("a\u{9F}b", "\"a\\x9Fb\""),
  ])
  func `characters YAML cannot hold raw are escaped`(
    text: String,
    expected: String,
  ) {
    #expect(writer.text(of: text, in: .block) == expected)
  }

  @Test
  func `a quoted text keeps what is printable as it is`() {
    let text = "a: 😀 日本語 é\u{A0}"

    #expect(writer.text(of: text, in: .block) == "\"\(text)\"")
  }

  @Test(arguments: NastyText.fixed)
  func `every text is read back exactly as a value`(text: String) throws {
    let value = try readBlock(writer.text(of: text, in: .block))

    guard case let .string(read)? = value else {
      Issue.record("not text: \(String(describing: value))")
      return
    }

    #expect(read.unicodeScalars.elementsEqual(text.unicodeScalars))
  }

  @Test(arguments: NastyText.fixed)
  func `every text is read back exactly as an item of a list on one line`(
    text: String,
  ) throws {
    let value = try readFlow(writer.text(of: text, in: .flow))

    guard case let .string(read)? = value else {
      Issue.record("not text: \(String(describing: value))")
      return
    }

    #expect(read.unicodeScalars.elementsEqual(text.unicodeScalars))
  }

  @Test(arguments: NastyText.fixed)
  func `every text is read back exactly as a key`(text: String) throws {
    let value = try reader.read(
      "\(writer.text(of: text, in: .block)): 1\n",
      file: "a.yml",
      kind: .useCase,
    )

    guard case let .object(members) = value, let key = members.first?.key else {
      Issue.record("not a mapping: \(value)")
      return
    }

    #expect(key.unicodeScalars.elementsEqual(text.unicodeScalars))
  }

  @Test
  func `a text the reader would type as something else is quoted whatever else is safe`() {
    struct MockTyper: PlainScalarTyping {
      func type(of _: String) -> PlainScalarTyped {
        .integerTooLarge
      }
    }

    #expect(YAMLScalarWriter(typer: MockTyper()).text(of: "plain", in: .block) == "\"plain\"")
  }
}
