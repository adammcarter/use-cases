import Testing
@testable import UseCasesCore

struct DefinitionFileLayoutTests {
  private static let two = """
  prefix: billing

  use_cases:
    - id: totals
      title: Totals
      scenarios:
        - id: s
          when: [x]

    - id: discounts
      title: Discounts
  """

  private func layout(_ text: String) throws -> DefinitionFileLayout {
    try DefinitionFileLayout(text: text)
  }

  @Test
  func `each use case runs from its dash to the next and its blank lines go with it`() throws {
    let layout = try layout(Self.two)
    try #require(layout.items.count == 2)

    #expect(layout.items.count == 2)
    #expect(layout.itemIndent == 2)
    #expect(layout.items[0].start == 3)
    #expect(layout.items[0].ownEnd == 8)
    #expect(layout.items[0].gapEnd == 9)
    #expect(layout.items[0].gap == 1)
    #expect(layout.items[1].start == 9)
    #expect(layout.items[1].gap == 0)
  }

  @Test
  func `a list whose dashes are not indented is read too`() throws {
    let layout = try layout("use_cases:\n- id: a\n  title: A\n- id: b\n  title: B\nprefix: x\n")
    try #require(layout.items.count == 2)

    #expect(layout.itemIndent == 0)
    #expect(layout.items.map(\.start) == [1, 3])
    #expect(layout.items[1].ownEnd == 5)
  }

  @Test
  func `a comment directly above a use case belongs to that use case`() throws {
    let layout = try layout(
      "use_cases:\n  # first\n  - id: a\n    title: A\n\n"
        + "  # about b\n  # more\n  - id: b\n    title: B\n",
    )
    try #require(layout.items.count == 2)

    #expect(layout.items[0].attachedStart == 1)
    #expect(layout.items[0].leadingComments.map(\.text) == ["# first"])
    #expect(layout.items[0].gapEnd == 5)
    #expect(layout.items[1].attachedStart == 5)
    #expect(layout.items[1].leadingComments.map(\.text) == ["# about b", "# more"])
    #expect(layout.items[0].innerComments.isEmpty)
  }

  @Test
  func `a comment with a blank line below it is nobody's and stays out of both`() throws {
    let layout = try layout(
      "use_cases:\n  - id: a\n    title: A\n  # alone\n\n  - id: b\n    title: B\n",
    )
    try #require(layout.items.count == 2)

    #expect(layout.items[0].ownEnd == 3)
    #expect(layout.items[0].innerComments.isEmpty)
    #expect(layout.items[1].leadingComments.isEmpty)
  }

  @Test
  func `comments inside a use case are listed with their lines`() throws {
    let layout = try layout(
      "use_cases:\n  - id: a  # one\n    # two\n    title: A\n    intent: |\n      # text\n",
    )
    try #require(layout.items.count == 1)

    #expect(layout.items[0].innerComments == [
      FileComment(line: 2, text: "# one"),
      FileComment(line: 3, text: "# two"),
    ])
  }

  @Test
  func `blank lines after a block that keeps them are its text`() throws {
    let layout = try layout(
      "use_cases:\n  - id: a\n    intent: |+\n      text\n\n\n  - id: b\n    title: B\n",
    )
    try #require(layout.items.count == 2)

    #expect(layout.items[0].keepsBlankLines)
    #expect(layout.items[0].gap == 0)
    #expect(layout.items[0].contentEnd == 6)
  }

  @Test
  func `a file written with carriage returns is edited with them`() throws {
    let layout = try layout("use_cases:\r\n  - id: a\r\n    title: A\r\n")

    #expect(layout.lineBreak == "\r\n")
    #expect(layout.lines == ["use_cases:", "  - id: a", "    title: A"])
    #expect(layout.text(of: layout.lines) == "use_cases:\r\n  - id: a\r\n    title: A\r\n")
  }

  @Test
  func `a file that does not end with a line break does not gain one`() throws {
    let layout = try layout("use_cases:\n  - id: a\n    title: A")

    #expect(layout.endsWithLineBreak == false)
    #expect(layout.text(of: layout.lines) == "use_cases:\n  - id: a\n    title: A")
  }

  @Test
  func `every comment of the file is listed`() throws {
    let layout = try layout("# top\nprefix: a\nuse_cases:\n  - id: a # side\n    title: A\n")

    #expect(layout.comments.map(\.line) == [1, 4])
  }

  @Test(arguments: [
    ("prefix: a\n", DefinitionFileLayoutError.notFound),
    ("use_cases: []\n", .notAList),
    ("use_cases: [{ id: a }]\n", .notAList),
    ("use_cases:\n", .notAList),
  ])
  func `a file whose use cases are not a dashed list cannot be found by lines`(
    text: String,
    error: DefinitionFileLayoutError,
  ) {
    #expect(throws: error) {
      try DefinitionFileLayout(text: text)
    }
  }

  // MARK: - Plain text with quote marks in it

  private static let apostrophes = """
  use_cases:
    - id: a
      title: A
      intent: Built in the '90s style

    # about b
    - id: b
      title: "B" # why
      intent: say "hello

    - id: c
      title: C
  """

  @Test
  func `quote marks in plain text do not hide the comments and use cases after them`() throws {
    let layout = try layout(Self.apostrophes)
    try #require(layout.items.count == 3)

    #expect(layout.items.count == 3)
    #expect(layout.items[1].leadingComments.map(\.text) == ["# about b"])
    #expect(layout.items[1].innerComments.map(\.text) == ["# why"])
    #expect(layout.items[0].gap == 1)
    #expect(layout.items[1].gap == 1)
    #expect(layout.comments.map(\.line) == [6, 8])
  }

  // MARK: - A block ends at the first line indented less than its text

  @Test
  func `a comment indented less than a block's text, in the use case, is a comment of it`() throws {
    let layout = try layout(
      "use_cases:\n  - id: a\n    intent: |\n        text\n      # real comment\n    title: A\n",
    )
    try #require(layout.items.count == 1)

    #expect(layout.items[0].innerComments == [FileComment(line: 5, text: "# real comment")])
  }

  // MARK: - Header lines that are valid

  @Test(arguments: [
    "\u{FEFF}use_cases:\n  - id: a\n",
    "use_cases: # c  \n  - id: a\n",
    "use_cases:\t\n  - id: a\n",
    "use_cases:   \n  - id: a\n",
    "\"use_cases\":\n  - id: a\n",
    "'use_cases':\n  - id: a\n",
    "use_cases :\n  - id: a\n",
    "# top\nuse_cases:\n  - id: a\n",
    "prefix: x\nuse_cases:\n  - id: a\n",
  ])
  func `a header line that is valid YAML is found`(text: String) throws {
    #expect(try layout(text).items.count == 1)
  }

  @Test
  func `a header line ending in a carriage return in a file that is not all carriage returns`(
  ) throws {
    let layout = try layout("prefix: x\nuse_cases:\r\n  - id: a\r\n  - id: b\n")
    try #require(layout.items.count == 2)

    #expect(layout.lineBreak == "\n")
    #expect(layout.items.count == 2)
    #expect(layout.items[0].start == 2)
  }

  @Test
  func `a byte order mark before the first key is not part of the line`() throws {
    let layout = try layout("\u{FEFF}# top\nuse_cases:\n  - id: a\n")

    #expect(layout.items.count == 1)
    #expect(layout.lines[0] == "\u{FEFF}# top")
    #expect(layout.comments.first?.line == 1)
  }

  @Test(arguments: [
    ("use_cases: # c  \n", DefinitionFileLayoutError.notAList),
    ("use_cases: [] # c\n", .notAList),
    ("use_cases_dir: x\n", .notFound),
  ])
  func `a header that is not a dashed list is refused for the real reason`(
    text: String,
    error: DefinitionFileLayoutError,
  ) {
    #expect(throws: error) {
      try DefinitionFileLayout(text: text)
    }
  }
}
