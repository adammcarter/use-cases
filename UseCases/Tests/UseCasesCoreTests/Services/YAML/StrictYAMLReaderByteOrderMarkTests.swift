import Testing
@testable import UseCasesCore

struct StrictYAMLReaderByteOrderMarkTests {
  private let reader = StrictYAMLReader()

  // Mutant: the check left out, or run on plain text only.
  @Test(arguments: [
    "title: \u{FEFF}x\n",
    "title: \"\u{FEFF}x\"\n",
    "title: '\u{FEFF}x'\n",
    "title: \"\\uFEFFx\"\n",
    "title: \"\\ufeffx\"\n",
    "title: \"\\U0000FEFFx\"\n",
    "title: |\n  \u{FEFF}x\n",
    "title: |-\n  \u{FEFF}x\n",
    "title: >\n  \u{FEFF}x\n",
    "title: |2\n  \u{FEFF}x\n",
    "\"\u{FEFF}k\": 1\n",
    "\"\\uFEFFk\": 1\n",
    "when: [\"\\uFEFFx\"]\n",
    "when:\n  - \u{FEFF}x\n",
    "when:\n  a: \"\u{FEFF}x\"\n",
    "title: &anchor \"\\uFEFFx\"\n",
  ])
  func `a text that starts with a byte order mark is refused, however it is written`(
    text: String,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    guard case .leadingByteOrderMark = error else {
      Issue.record("not a byte order mark refusal: \(error)")
      return
    }

    #expect(error.message.contains("byte order mark"))
    #expect(error.message.contains("U+FEFF"))
  }

  @Test
  func `the refusal says which line`() throws {
    let error = try #require(
      reader.attempt("a: 1\nb: 2\ntitle: \"\\uFEFFx\"\n", file: "stdin").failure,
    )

    #expect(error.line == 3)
    #expect(error.message.hasPrefix("stdin:3: text that starts with a byte order mark (U+FEFF)"))
  }

  // Mutant: any byte order mark refused, not only one that starts a text.
  @Test(arguments: [
    "title: x\u{FEFF}y\n",
    "title: \"x\u{FEFF}y\"\n",
    "title: \"x\\uFEFFy\"\n",
    "title: 'x\u{FEFF}y'\n",
    "title: |\n  x\u{FEFF}y\n",
    "title: |\n  line\n  \u{FEFF}second\n",
    "when: [\"a\", \"b\\uFEFF\"]\n",
    "title: \" \\uFEFFx\"\n",
  ])
  func `a byte order mark inside a text is kept`(text: String) throws {
    let value = try #require(reader.attempt(text).success)

    guard case let .object(members) = value else {
      Issue.record("not a mapping")
      return
    }

    #expect(members.count == 1)
  }

  @Test
  func `a byte order mark inside a text is read back as it was written`() throws {
    let value = try #require(reader.attempt("title: \"x\\uFEFFy\"\n").success)

    #expect(value == .members(["title": .string("x\u{FEFF}y")]))
  }

  @Test
  func `the one that starts the file is still ignored`() throws {
    let value = try #require(reader.attempt("\u{FEFF}title: x\n").success)

    #expect(value == .members(["title": .string("x")]))
  }

  @Test
  func `a blank line first means the text starts with a line break, not the mark`() throws {
    let value = try #require(reader.attempt("title: |\n\n  \u{FEFF}x\n").success)

    #expect(value == .members(["title": .string("\n\u{FEFF}x\n")]))
  }

  @Test
  func `a settings file refuses it too: it is the same text everywhere`() throws {
    let error = try #require(reader.attempt("title: \"\\uFEFFx\"\n", kind: .settings).failure)

    guard case .leadingByteOrderMark = error else {
      Issue.record("not a byte order mark refusal: \(error)")
      return
    }
  }
}
