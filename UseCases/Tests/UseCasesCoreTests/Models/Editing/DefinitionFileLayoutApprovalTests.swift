import Testing
@testable import UseCasesCore

/// Where the `approved` field of a use case is, so that it can be written without touching a
/// line outside it.
struct DefinitionFileLayoutApprovalTests {
  private func layout(_ text: String) throws -> DefinitionFileLayout {
    try DefinitionFileLayout(text: text)
  }

  private func item(_ text: String) throws -> DefinitionFileLayout.Item {
    try #require(layout(text).items.first)
  }

  @Test
  func `a use case with no approval has the column of its fields and no approved range`() throws {
    let item = try item("use_cases:\n  - id: a\n    title: A\n")

    #expect(item.fieldIndent == 4)
    #expect(item.approved == nil)
  }

  @Test
  func `the approved field runs from its key to the line before the next field`() throws {
    let item = try item(
      """
      use_cases:
        - id: a
          approved:
            by: Sam
            "on": "2026-10-20"
            behaviour: abc
          title: A
      """,
    )

    #expect(item.approved == 2 ..< 6)
  }

  @Test
  func `the last field of the use case ends where the use case does`() throws {
    let item = try item(
      """
      use_cases:
        - id: a
          title: A
          approved:
            by: Sam

        - id: b
      """,
    )

    #expect(item.approved == 3 ..< 5)
  }

  @Test
  func `comments and blank lines after the field belong to what follows it`() throws {
    let item = try item(
      """
      use_cases:
        - id: a
          approved:
            by: Sam

          # about the title
          title: A
      """,
    )

    #expect(item.approved == 2 ..< 4)
  }

  @Test
  func `a comment inside the approved field is part of it`() throws {
    let item = try item(
      """
      use_cases:
        - id: a
          approved:
            # who
            by: Sam
          title: A
      """,
    )

    #expect(item.approved == 2 ..< 5)
  }

  @Test(arguments: [
    "approved: { by: Sam }",
    "\"approved\": { by: Sam }",
    "'approved' : { by: Sam }",
  ])
  func `the key may be quoted and a flow mapping is one line`(field: String) throws {
    let item = try item("use_cases:\n  - id: a\n    \(field)\n    title: A\n")

    #expect(item.approved == 2 ..< 3)
  }

  @Test
  func `a key that only starts with approved is not the field`() throws {
    let item = try item("use_cases:\n  - id: a\n    approved_by: Sam\n    title: A\n")

    #expect(item.approved == nil)
  }

  @Test
  func `the word approved inside a block of text is not the field`() throws {
    let item = try item(
      """
      use_cases:
        - id: a
          description: |
            approved: no
          title: A
      """,
    )

    #expect(item.approved == nil)
  }

  @Test
  func `an item of a list written in the column of the fields does not end the field before it`()
    throws
  {
    let item = try item(
      """
      use_cases:
        - id: a
          approved:
          - by
          - Sam
          title: A
      """,
    )

    #expect(item.approved == 2 ..< 5)
  }

  @Test
  func `the fields may start on the line after the dash`() throws {
    let item = try item("use_cases:\n  -\n    id: a\n    title: A\n")

    #expect(item.fieldIndent == 4)
  }

  @Test
  func `fields further in than a dash and a space are found where they are`() throws {
    let item = try item("use_cases:\n  -   id: a\n      title: A\n      approved: {}\n")

    #expect(item.fieldIndent == 6)
    #expect(item.approved == 3 ..< 4)
  }

  @Test(arguments: ["{ id: a, title: A }", "[a]"])
  func `a use case written as a flow collection has no fields to find`(written: String) throws {
    let item = try item("use_cases:\n  - \(written)\n")

    #expect(item.fieldIndent == nil)
    #expect(item.approved == nil)
  }

  @Test
  func `approved on the line of the dash cannot be told from the dash`() throws {
    let item = try item("use_cases:\n  - approved: {}\n    id: a\n")

    #expect(item.fieldIndent == nil)
  }

  @Test
  func `the field is set where it is, and only there`() throws {
    let text = "use_cases:\n  - id: a\n    approved: old\n    title: A\n"
    let layout = try layout(text)

    let lines = layout.settingApproval(
      of: 0,
      to: ["    approved:", "      by: Sam"],
    )

    #expect(lines == ["use_cases:", "  - id: a", "    approved:", "      by: Sam", "    title: A"])
  }

  @Test
  func `a use case with none is given the field after its last line, before the gap`() throws {
    let text = "use_cases:\n  - id: a\n    title: A\n\n  - id: b\n    title: B\n"
    let layout = try layout(text)

    let lines = layout.settingApproval(
      of: 0,
      to: ["    approved:", "      by: Sam"],
    )

    #expect(lines == [
      "use_cases:", "  - id: a", "    title: A", "    approved:", "      by: Sam", "",
      "  - id: b", "    title: B",
    ])
  }

  @Test
  func `a use case that ends in a block that keeps its blank lines is given the field after them`()
    throws
  {
    let text = "use_cases:\n  - id: a\n    description: |+\n      text\n\n\n  - id: b\n"
    let layout = try layout(text)

    let lines = layout.settingApproval(
      of: 0,
      to: ["    approved: {}"],
    )

    #expect(lines == [
      "use_cases:", "  - id: a", "    description: |+", "      text", "", "", "    approved: {}",
      "  - id: b",
    ])
  }
}
