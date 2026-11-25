import Testing
@testable import UseCasesCore

struct UseCaseApplierTests {
  private let fixture: BatchFixture

  init() throws {
    fixture = try BatchFixture()
  }

  private func applier(sending json: String) throws -> UseCaseApplier {
    try UseCaseApplier(
      reader: UseCaseBatchReader(
        reader: MockAuthoredInput(AuthoredInput(name: "stdin", value: authored(json))),
        checker: UseCaseInputChecker(),
      ),
      planner: UseCaseBatchPlanner(calendar: MockCalendarDay("2026-10-20")),
    )
  }

  private func plan(
    _ json: String,
    approvedBy approver: String? = nil,
  ) throws -> UseCaseBatchChange {
    try applier(sending: json).plan(
      applyingFrom: "-",
      approvedBy: approver,
      in: fixture.loaded(),
      links: [],
    )
  }

  @Test
  func `a batch read is planned in the workspace`() throws {
    let change = try plan(
      #"{"remove": ["app.solo.only"], "save": [{"id": "app.dark.x", "title": "X"}]}"#,
    )

    #expect(change.useCases.map(\.identifier) == ["app.solo.only", "app.dark.x"])
    #expect(change.root == fixture.workspace.directory.url)
  }

  @Test
  func `the name of who signed off is trimmed before it is recorded`() throws {
    let change = try plan(
      #"{"save": [{"id": "app.dark.x", "title": "X"}]}"#,
      approvedBy: "  Sam  ",
    )
    let text = try #require(change.writes.changes.first?.text)

    #expect(text.contains("by: Sam\n"))
  }

  @Test(arguments: ["", " ", "\n"])
  func `a blank name is refused before the input is looked at`(name: String) {
    #expect(
      throws: UseCaseBatchError.approver(
        reason: "--approved-by names who signed off, so it cannot be blank",
      ),
    ) {
      try plan(
        "{}",
        approvedBy: name,
      )
    }
  }

  @Test
  func `a name longer than two hundred characters is refused`() {
    let name = String(repeating: "a", count: 201)

    #expect(throws: UseCaseBatchError.self) {
      try plan(
        #"{"remove": ["app.solo.only"]}"#,
        approvedBy: name,
      )
    }
  }

  @Test
  func `an input that is not a batch is refused`() {
    #expect(throws: UseCaseBatchError.notABatch(
      name: "stdin",
      problem: "this one changes nothing",
    )) {
      try plan(#"{"save": []}"#)
    }
  }

  @Test
  func `the working directory the applier reads files from is the one it is given`() throws {
    try fixture.workspace.write("batch.yml", "remove: [app.solo.only]\n")

    let applier = UseCaseApplier(workingDirectory: fixture.workspace.directory.url)
    let change = try applier.plan(
      applyingFrom: "batch.yml",
      approvedBy: nil,
      in: fixture.loaded(),
      links: [],
    )

    #expect(change.useCases.map(\.action) == [.removed])
  }
}
