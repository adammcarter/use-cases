import Testing
@testable import UseCasesCore

struct SchemaPatternTests {
  static let name = #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$(?!\n)"#
  static let namespace =
    #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$(?!\n)"#
  static let projectPath =
    #"^(?!/)(?![A-Za-z]:)(?!.*(?:^|/)\.\.(?:/|$))(?!.*\\)[^\u0000-\u001f\u007f]+$(?!\n)"#

  @Test(arguments: [
    (namespace, "calc.add", true),
    (namespace, "calc", true),
    (namespace, "calc.add\n", false),
    (namespace, "calc\n", false),
    (namespace, "calc.add\r\n", false),
    (namespace, "calc.add\r", false),
    (namespace, "calc.add\u{85}", false),
    (namespace, "calc.add\u{2028}", false),
    (namespace, "\ncalc.add", false),
    (namespace, "calc\n.add", false),
    (namespace, "calc.add ", false),
    (namespace, "Calc.add", false),
    (namespace, "calc..add", false),
    (namespace, "", false),
    (name, "toggle", true),
    (name, "toggle\n", false),
    (name, "toggle-", false),
    (name, "é", false),
  ])
  func `a name ending in a line break is refused by the id patterns`(
    pattern: String,
    text: String,
    expected: Bool,
  ) throws {
    #expect(try matches(pattern, text) == expected)
  }

  @Test(arguments: [
    ("src/a.swift", true),
    ("café/é.txt", true),
    ("a b/c", true),
    ("a\\b", false),
    ("/etc/passwd", false),
    ("C:/x", false),
    ("..", false),
    ("a/..", false),
    ("../a", false),
    ("a/../b", false),
    ("a/..b", true),
    ("a\u{0}b", false),
    ("a\u{1}b", false),
    ("a\u{1f}b", false),
    ("a\u{7f}b", false),
    ("a\u{20}b", true),
    ("a\nb", false),
    ("a\n", false),
    ("a\u{85}/../b", false),
    ("", false),
  ])
  func `a project path pattern reads its unicode escapes and its dot`(
    text: String,
    expected: Bool,
  ) throws {
    #expect(try matches(Self.projectPath, text) == expected)
  }

  @Test
  func `a dot stops at the line terminators ECMA-262 names and no others`() throws {
    let pattern = "^a.b$"

    #expect(try matches(pattern, "axb"))
    #expect(try matches(pattern, "a\u{85}b"))
    #expect(try matches(pattern, "a\u{0B}b"))
    #expect(try matches(pattern, "a\u{0C}b"))
    #expect(try !matches(pattern, "a\nb"))
    #expect(try !matches(pattern, "a\rb"))
    #expect(try !matches(pattern, "a\u{2028}b"))
    #expect(try !matches(pattern, "a\u{2029}b"))
  }

  @Test
  func `a dot inside a class and an escaped dot are left as they are`() throws {
    #expect(try matches(#"^a[.]b$"#, "a.b"))
    #expect(try !matches(#"^a[.]b$"#, "axb"))
    #expect(try matches(#"^a\.b$"#, "a.b"))
    #expect(try !matches(#"^a\.b$"#, "axb"))
    #expect(try matches(#"^a[\].]b$"#, "a.b"))
  }

  @Test(arguments: [
    ("^x$", "x", true),
    ("^x$", "x\n", false),
    ("^x$", "x\r", false),
    ("^x$", "x\u{2028}", false),
    ("^b", "a\nb", false),
    ("a$", "a\nb", false),
    (#"\{(?!report\})[^{}]*\}"#, "swift test {use-case-id}", true),
    (#"\{(?!report\})[^{}]*\}"#, "{report}", false),
    (#"\{(?!report\})[^{}]*\}"#, "--output={report}", false),
    ("b", "abc", true),
    ("^[A-Za-z0-9_-]$", "-", true),
  ])
  func `a pattern is a search whose anchors only match at the ends of the text`(
    pattern: String,
    text: String,
    expected: Bool,
  ) throws {
    #expect(try matches(pattern, text) == expected)
  }

  @Test(arguments: ["(", "[a", "a{2,1}", "*a", "(?<n"])
  func `text that is not a regular expression has no regex`(source: String) {
    #expect(SchemaPattern(source: source).makeRegex() == nil)
  }

  @Test(arguments: [
    (#"^\d+$"#, #"\d"#),
    (#"\D"#, #"\D"#),
    (#"\w"#, #"\w"#),
    (#"[\w-]"#, #"\w"#),
    (#"\S"#, #"\S"#),
    (#"\bword\b"#, #"\b"#),
    (#"\B"#, #"\B"#),
    (#"\p{L}"#, #"\p"#),
    (#"\P{L}"#, #"\P"#),
    (#"a\z"#, #"\z"#),
    (#"\Aa"#, #"\A"#),
    (#"a\Z"#, #"\Z"#),
    (#"(a)\1"#, #"\1"#),
    (#"\k<n>"#, #"\k"#),
    (#"\x41"#, #"\x"#),
    (#"\u12"#, #"\u"#),
    (#"\0"#, #"\0"#),
    (#"abc\"#, #"\"#),
    ("(?i)abc", "(?i"),
    ("(?s)a.b", "(?s"),
    ("(?x) a", "(?x"),
    ("(?#comment)", "(?#"),
    ("(?<n>x)", "(?<"),
    ("(?<=x)y", "(?<"),
    ("(?", "(?"),
    ("[[:alpha:]]", "[ inside a character class"),
    ("[a[b]]", "[ inside a character class"),
    ("[a&&b]", "&& inside a character class"),
    ("[a--b]", "-- inside a character class"),
    ("[a~~b]", "~~ inside a character class"),
  ])
  func `syntax the two regular expression languages read differently is reported`(
    source: String,
    construct: String,
  ) {
    let pattern = SchemaPattern(source: source)

    #expect(pattern.unsupportedSyntax == construct)
    #expect(pattern.makeRegex() == nil)
  }

  @Test(arguments: [
    SchemaPatternTests.name,
    SchemaPatternTests.namespace,
    SchemaPatternTests.projectPath,
    #"\{(?!report\})[^{}]*\}"#,
    "^[A-Za-z0-9_-]$",
    #"^a[.]b$"#,
    #"^a[\].]b$"#,
    #"^(?:[Cc][Oo][Nn]|[Pp][Rr][Nn])(?:\..*)?$(?!\n)"#,
    #"^(?!\.use-cases(?:/|$))"#,
    #"(?=x)\t\r\n\\\/\-"#,
    #"\u0000"#,
    "a|b",
    "a{2,3}b?c*d+",
    #"^[^\s:]+$"#,
    #"\s"#,
  ])
  func `the syntax the bundled schemas use is supported`(source: String) {
    let pattern = SchemaPattern(source: source)

    #expect(pattern.unsupportedSyntax == nil)
    #expect(pattern.makeRegex() != nil)
  }

  @Test(arguments: [
    ("a", false),
    ("", false),
    (" ", true),
    ("\t", true),
    ("\n", true),
    ("\u{0B}", true),
    ("\u{0C}", true),
    ("\r", true),
    ("\u{A0}", true),
    ("\u{1680}", true),
    ("\u{2000}", true),
    ("\u{200A}", true),
    ("\u{2028}", true),
    ("\u{2029}", true),
    ("\u{202F}", true),
    ("\u{205F}", true),
    ("\u{3000}", true),
    ("\u{FEFF}", true),
    ("\u{85}", false),
    ("\u{1C}", false),
    ("\u{180E}", false),
    ("\u{200B}", false),
  ])
  func `a backslash s is the ECMA-262 set of white space and line terminators`(
    text: String,
    isWhiteSpace: Bool,
  ) throws {
    #expect(try matches(#"^\s$"#, text) == isWhiteSpace)
    #expect(try matches(#"^[\s]$"#, text) == isWhiteSpace)
    #expect(try matches(#"^[^\s]$"#, text) == (!isWhiteSpace && !text.isEmpty))
  }

  @Test(arguments: [
    ("uc-route-v1-sha256:abc", true),
    ("uc-route-v1-sha256:a b", false),
    ("uc-route-v1-sha256:a\u{FEFF}b", false),
    ("uc-route-v1-sha256:a:b", false),
    ("uc-route-v1-sha256:a\u{85}b", true),
  ])
  func `a class of anything but white space and a colon refuses both`(
    text: String,
    expected: Bool,
  ) throws {
    #expect(try matches(#"^uc-route-v1-sha256:[^\s:]+$"#, text) == expected)
  }

  private func matches(
    _ pattern: String,
    _ text: String,
  ) throws -> Bool {
    let regex = try #require(SchemaPattern(source: pattern).makeRegex())

    return text.firstMatch(of: regex) != nil
  }
}
