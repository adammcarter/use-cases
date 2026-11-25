import Testing
@testable import UseCasesCore

/// A sign-off is written into the lines of a use case's `approved` field and nowhere else.
struct DefinitionFileEditorApprovalTests {
  private static let approval = Approval(
    approver: "Kim",
    day: "2026-10-20",
    behaviour: String(repeating: "ab", count: 32),
  )

  private static let zeros = String(repeating: "0", count: 64)

  private static let noted = """
  # kept
  prefix: noted
  use_cases:
    # about the item
    - id: item
      title: 'Item' # odd quoting
      value_tier: core
      # about the intent
      intent: "Readable."
      scenarios:
        - id: on-state
          when: [x]
          then: [y]
      bindings: []
      description: |
        Block
        text

    - id: other
      title: Other

  """

  private let editor = DefinitionFileEditor()
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("use-cases/noted.yml", Self.noted)
  }

  private func approve(
    _ identifier: String = "app.noted.item",
    with approval: Approval = approval,
  ) throws -> EditedDefinitionFile {
    try editor.edit(
      .approve(
        UseCaseIdentifier(validating: identifier),
        with: approval,
      ),
      in: fixture.loaded(),
    )
  }

  private func lines(_ text: String) -> [String] {
    text.components(separatedBy: "\n")
  }

  @Test
  func `the field is added after the last line of the use case and nothing else changes`() throws {
    let edited = try approve()
    let after = lines(edited.change.text)
    let start = try #require(after.firstIndex(of: "    approved:"))
    var rest = after

    rest.removeSubrange(start ..< start + 4)

    #expect(rest == lines(Self.noted))
    #expect(after[start...].prefix(4) == [
      "    approved:",
      "      by: Kim",
      "      \"on\": \"2026-10-20\"",
      "      behaviour: \(Self.approval.behaviour)",
    ])
    #expect(edited.droppedComments.isEmpty)
  }

  @Test
  func `the field is written in the column the use case's fields are in`() throws {
    try fixture.write(
      "use-cases/wide.yml",
      "prefix: wide\nuse_cases:\n  -   id: item\n      title: Item\n",
    )

    let edited = try approve("app.wide.item")

    #expect(lines(edited.change.text).contains("      approved:"))
  }

  @Test
  func `a field that is there is written again where it is, and nothing else changes`() throws {
    let written = Approval(
      approver: "Sam",
      day: "2026-01-02",
      behaviour: String(repeating: "cd", count: 32),
    )
    try fixture.write(
      "use-cases/noted.yml",
      Self.noted.replacingOccurrences(
        of: "    bindings: []\n",
        with: "    approved: { by: Sam, \"on\": \"2026-01-01\", behaviour: \"" + Self.zeros
          + "\" }\n    bindings: []\n",
      ),
    )

    let edited = try approve(with: written)
    let after = lines(edited.change.text)

    #expect(after.contains("      by: Sam"))
    #expect(!after.contains { line in line.hasPrefix("    approved: {") })
    #expect(after.filter { line in line.contains("approved") }.count == 1)
    #expect(after.contains("    bindings: []"))
  }

  @Test
  func `a comment inside the field that is written again is dropped and listed`() throws {
    try fixture.write(
      "use-cases/noted.yml",
      Self.noted.replacingOccurrences(
        of: "    bindings: []\n",
        with: "    approved:\n      # who\n      by: Sam\n      \"on\": \"2026-01-01\"\n"
          + "      behaviour: \"\(Self.zeros)\"\n    bindings: []\n",
      ),
    )

    let edited = try approve()

    #expect(edited.droppedComments.count == 1)
    #expect(edited.droppedComments.first?.contains("# who") == true)
    #expect(edited.change.text.contains("# who") == false)
    #expect(edited.change.text.contains("# about the intent"))
  }

  @Test
  func `the change is held to the file as it was read`() throws {
    let edited = try approve()

    #expect(edited.change.action == .replace)
    #expect(edited.change.expected == Array(Self.noted.utf8))
  }

  @Test
  func `the use case read back is the one signed off and the others are as they were`() throws {
    let edited = try approve()
    let before = try fixture.loaded().useCases
    try fixture.write("use-cases/noted.yml", edited.change.text)
    let after = try fixture.loaded().useCases

    #expect(after.first { $0.identifier.text == "app.noted.item" }?.definition.approval
      == Self.approval)
    #expect(
      after.first { $0.identifier.text == "app.noted.other" }?.definition
        == before.first { $0.identifier.text == "app.noted.other" }?.definition,
    )
  }

  @Test
  func `a use case written as a flow mapping cannot be signed off by its lines`() throws {
    try fixture.write(
      "use-cases/flow.yml",
      "prefix: flow\nuse_cases:\n  - { id: item, title: Item }\n",
    )

    #expect(
      throws: UseCaseEditingError.unsupportedLayout(
        file: "use-cases/flow.yml",
        reason: "app.flow.item is not written as a block mapping, so its sign-off cannot be "
          + "written into its lines",
      ),
    ) {
      try approve("app.flow.item")
    }
  }

  @Test
  func `a use case that is not there cannot be signed off`() {
    #expect(throws: UseCaseEditingError.unknown(identifier: "app.noted.nope")) {
      try approve("app.noted.nope")
    }
  }
}
