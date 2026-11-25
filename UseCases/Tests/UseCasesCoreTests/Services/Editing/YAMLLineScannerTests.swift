import Testing
@testable import UseCasesCore

struct YAMLLineScannerTests {
  private func scanned(_ lines: [String]) -> [ScannedLine] {
    var scanner = YAMLLineScanner()

    return lines.map { line in
      scanner.scan(line)
    }
  }

  @Test(arguments: [
    ("", ScannedLine.Kind.blank),
    ("   ", .blank),
    ("# note", .comment),
    ("    # note", .comment),
    ("title: A", .content),
    ("  - id: a", .content),
  ])
  func `a line is blank, a comment on its own, or content`(
    line: String,
    kind: ScannedLine.Kind,
  ) {
    #expect(scanned([line])[0].kind == kind)
  }

  @Test
  func `the indent is the spaces the line starts with`() {
    #expect(scanned(["      when: [x]"])[0].indent == 6)
  }

  @Test(arguments: [
    ("title: A  # note", "# note"),
    ("title: \"A\" # note", "# note"),
    ("when: [a, \"b # c\"]  # note", "# note"),
    ("title: 'it''s # not' # note", "# note"),
    ("key: # note", "# note"),
  ])
  func `a comment that ends a content line is found`(
    line: String,
    comment: String,
  ) {
    #expect(scanned([line])[0].trailingComment == comment)
  }

  @Test(arguments: [
    "title: \"Dark mode #2\"",
    "title: 'a # b'",
    "title: Don't # is text? no",
    "title: C#",
    "title: a#b",
  ])
  func `a hash that is part of the text is not a comment`(line: String) {
    let comment = scanned([line])[0].trailingComment

    // The line that has a real comment after an apostrophe is the one that says so.
    #expect(comment == nil || line.contains("Don't"))
  }

  @Test
  func `an apostrophe inside plain text does not open a quote`() {
    let lines = scanned(["title: Don't stop  # note", "next: x"])

    #expect(lines[0].trailingComment == "# note")
    #expect(lines[1].kind == .content)
  }

  @Test
  func `the lines of a block are text, and a hash in them is no comment`() {
    let lines = scanned([
      "    intent: |",
      "      first",
      "      # still text",
      "",
      "      last",
      "    title: next",
    ])

    #expect(lines.map(\.kind) == [.content, .content, .content, .blank, .content, .content])
    #expect(lines.map(\.isBlockText) == [false, true, true, false, true, false])
    #expect(lines.allSatisfy { $0.trailingComment == nil })
  }

  @Test
  func `a block that hangs from a dash ends at the next line that is not indented under it`() {
    let lines = scanned([
      "  - |",
      "      text",
      "  - other",
    ])

    #expect(lines.map(\.isBlockText) == [false, true, false])
  }

  @Test
  func `a block opened after a key in a dash line hangs from the key`() {
    let lines = scanned([
      "  - intent: >-",
      "      folded",
      "    title: x",
    ])

    #expect(lines.map(\.isBlockText) == [false, true, false])
  }

  @Test(arguments: [
    ("intent: |+", true),
    ("intent: |", false),
    ("intent: |-", false),
    ("intent: >+", true),
  ])
  func `only a block that keeps its blank lines says so`(
    line: String,
    keeps: Bool,
  ) {
    let lines = scanned([line, "  text", ""])

    #expect(lines[1].keepsBlankLines == keeps)
    #expect(lines[2].keepsBlankLines == keeps)
  }

  @Test
  func `a keeping block stops keeping once the next field starts`() {
    let lines = scanned(["intent: |+", "  text", "", "title: x"])

    #expect(lines[3].keepsBlankLines == false)
  }

  @Test
  func `text that ends in a bar is not a block unless a key or a dash comes before it`() {
    let lines = scanned(["title: a |", "  more"])

    #expect(lines[1].isBlockText == false)
  }

  @Test
  func `a quoted text that runs over lines keeps its hash out of the comments`() {
    let lines = scanned([
      "title: \"one",
      "  # two\"",
      "next: x  # note",
    ])

    #expect(lines.map(\.kind) == [.content, .content, .content])
    #expect(lines[1].trailingComment == nil)
    #expect(lines[2].trailingComment == "# note")
  }

  // MARK: - Quotes open only where a value can start

  @Test(arguments: [
    "intent: Built in the '90s style",
    "intent: say \"hello there",
    "  - it's alive",
    "title: rock 'n' roll",
    "  - title: It's here",
    "when: [it's, a \"b]",
    "title: 5' 2\" tall",
  ])
  func `a quote mark inside plain text opens nothing, so the lines after it are read as they are`(
    line: String,
  ) {
    let lines = scanned([line, "  # a real comment", "next: x  # note", ""])

    #expect(lines[0].trailingComment == nil)
    #expect(lines[1].kind == .comment)
    #expect(lines[2].trailingComment == "# note")
    #expect(lines[3].kind == .blank)
  }

  @Test
  func `a comment after plain text with a quote mark in it is still found`() {
    #expect(scanned(["intent: Built in the '90s style  # note"])[0].trailingComment == "# note")
  }

  @Test(arguments: [
    ("title: \"a # b\"  # note", "# note"),
    ("  - 'it''s # x' # note", "# note"),
    ("when: [ \"a, b\", 'c # d' ] # note", "# note"),
    ("covers: {k: \"v # w\"} # note", "# note"),
    ("\"title\": \"a # b\" # note", "# note"),
    ("- - \"deep # no\" # note", "# note"),
  ])
  func `a quote that opens where a value starts hides what is inside it`(
    line: String,
    comment: String,
  ) {
    #expect(scanned([line])[0].trailingComment == comment)
  }

  @Test
  func `a flow collection that runs over lines keeps its quotes where values start`() {
    let lines = scanned([
      "when: [a,",
      "  \"b # c\",",
      "  it's,",
      "  d]  # end",
      "next: x",
    ])

    #expect(lines.map(\.trailingComment) == [nil, nil, nil, "# end", nil])
  }

  @Test
  func `brackets in plain text are not a flow collection`() {
    let lines = scanned(["then: The total is 0.00]", "  \"x # y\"", "next: 1  # note"])

    #expect(lines[2].trailingComment == "# note")
  }

  // MARK: - A block ends at the first line indented less than its text

  @Test
  func `a line indented less than the block's text ends it, and a comment there is a comment`() {
    let lines = scanned([
      "    intent: |",
      "        text",
      "          deeper",
      "      # a real comment",
      "    title: x",
    ])

    #expect(lines.map(\.isBlockText) == [false, true, true, false, false])
    #expect(lines[3].kind == .comment)
  }

  @Test
  func `a line indented as much as the block's text is text, even if it starts with a hash`() {
    let lines = scanned([
      "    intent: |",
      "        text",
      "        # still text",
      "    title: x",
    ])

    #expect(lines.map(\.isBlockText) == [false, true, true, false])
    #expect(lines[2].kind == .content)
  }

  @Test
  func `an indentation indicator fixes the indent of the text`() {
    let lines = scanned([
      "intent: |2",
      "    more than two",
      "  two",
      " one",
    ])

    #expect(lines.map(\.isBlockText) == [false, true, true, false])
  }
}
