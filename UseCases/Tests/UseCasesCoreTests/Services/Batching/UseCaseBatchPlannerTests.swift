import Testing
@testable import UseCasesCore

struct UseCaseBatchPlannerTests {
  private let fixture: BatchFixture
  private let planner = UseCaseBatchPlanner(calendar: MockCalendarDay("2026-10-20"))

  init() throws {
    fixture = try BatchFixture()
  }

  private func plan(
    _ json: String,
    approvedBy approver: ApproverName? = nil,
    links: [ResolvedLink] = [],
  ) throws -> UseCaseBatchChange {
    try planner.plan(
      fixture.batch(json),
      approvedBy: approver,
      in: fixture.loaded(),
      links: links,
    )
  }

  private func steps(of change: UseCaseBatchChange) -> [String] {
    change.useCases.map { useCase in
      "\(useCase.action.rawValue) \(useCase.identifier)"
    }
  }

  @Test
  func `a batch runs every removal, then every addition, then every update, in the listed order`(
  ) throws {
    let change = try plan(
      """
      {"save": [
         {"id": "app.dark.toggle", "title": "Toggle, changed"},
         {"id": "app.refunds.partial", "title": "Partial"},
         {"id": "app.dark.other", "title": "Other, changed"},
         {"id": "app.refunds.full", "title": "Full"}],
       "remove": ["app.solo.only"]}
      """,
    )

    #expect(steps(of: change) == [
      "removed app.solo.only",
      "created app.refunds.partial",
      "added app.refunds.full",
      "replaced app.dark.toggle",
      "replaced app.dark.other",
    ])
  }

  @Test
  func `a file several changes touch is written once, and the files are listed by path`() throws {
    let change = try plan(
      """
      {"save": [{"id": "app.dark.toggle", "title": "A"}, {"id": "app.dark.other", "title": "B"},
                {"id": "app.refunds.partial", "title": "C"}],
       "remove": ["app.solo.only"]}
      """,
    )

    #expect(change.writes.changes.map(\.path) == [
      "use-cases/dark.yml", "use-cases/refunds.yml", "use-cases/solo.yml",
    ])
    #expect(change.writes.changes.map(\.action) == [.replace, .create, .delete])
  }

  @Test
  func `emptying a file and adding to its group in one batch replaces the file`() throws {
    let change = try plan(
      #"{"remove": ["app.solo.only"], "save": [{"id": "app.solo.again", "title": "Again"}]}"#,
    )

    #expect(steps(of: change) == ["removed app.solo.only", "created app.solo.again"])
    #expect(change.writes.changes.map(\.action) == [.replace])
    #expect(change.writes.changes.map(\.path) == ["use-cases/solo.yml"])
  }

  @Test
  func `two new use cases of a new group share one new file`() throws {
    let change = try plan(
      """
      {"save": [{"id": "app.refunds.partial", "title": "Partial"},
                {"id": "app.refunds.full", "title": "Full"}]}
      """,
    )

    #expect(steps(of: change) == ["created app.refunds.partial", "added app.refunds.full"])
    #expect(change.writes.changes.map(\.action) == [.create])
  }

  @Test
  func `a use case sent as it is written is unchanged and writes nothing`() throws {
    let change = try plan(fixture.savingAsShown("app.dark.toggle"))

    #expect(steps(of: change) == ["unchanged app.dark.toggle"])
    #expect(change.writes.isEmpty)
    #expect(change.warnings.isEmpty)
  }

  @Test
  func `nothing is written by the plan, only described`() throws {
    let before = fixture.text(of: "use-cases/dark.yml")

    _ = try plan(#"{"remove": ["app.dark.toggle"]}"#)

    #expect(fixture.text(of: "use-cases/dark.yml") == before)
  }

  @Test
  func `the workspace the batch leaves holds what was meant, and is not what it was`() throws {
    let change = try plan(
      """
      {"remove": ["app.dark.toggle"],
       "save": [{"id": "app.dark.contrast", "title": "Contrast"},
                {"id": "app.dark.other", "title": "Other, changed"}]}
      """,
    )

    #expect(try change.divergence(in: fixture.loaded()) != nil)
    #expect(try change.divergence(in: fixture.loadedAfter(change.writes)) == nil)
  }

  @Test
  func `markers that still name a removed use case are listed with the removal`() throws {
    let links = try [
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.solo.only",
        file: "tests/a.py",
        lines: 9 ... 11,
      ),
    ]

    let change = try plan(
      #"{"remove": ["app.solo.only"]}"#,
      links: links,
    )

    #expect(change.warnings == ["tests/a.py:9-11 is still marked for app.solo.only"])
  }

  @Test
  func `a comment inside a rewritten use case is dropped and listed, never silently`() throws {
    try fixture.workspace.write(
      "use-cases/noted.yml",
      "prefix: noted\nuse_cases:\n  - id: item\n    # about the title\n    title: Item\n",
    )

    let change = try plan(#"{"save": [{"id": "app.noted.item", "title": "Item, changed"}]}"#)

    #expect(change.warnings.count == 1)
    #expect(change.warnings.first?.contains("# about the title") == true)
  }

  @Test
  func `markers that still name removed use cases are listed together, by file and place`()
    throws
  {
    let links = try [
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.solo.only",
        file: "tests/b.py",
        lines: 5 ... 6,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        file: "tests/b.py",
        lines: 2 ... 3,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        file: "tests/a.py",
        lines: 30 ... 31,
      ),
    ]

    let change = try plan(
      #"{"remove": ["app.solo.only", "app.dark.toggle"]}"#,
      links: links,
    )

    #expect(change.warnings == [
      "tests/a.py:30-31 is still marked for app.dark.toggle",
      "tests/b.py:2-3 is still marked for app.dark.toggle",
      "tests/b.py:5-6 is still marked for app.solo.only",
    ])
  }

  // MARK: - Refused as a whole

  @Test(arguments: [
    #"{"remove": ["app.solo.only"], "save": [{"id": "app.solo.only", "title": "T"}]}"#,
    #"{"save": [{"id": "app.dark.x", "title": "A"}, {"id": "app.dark.x", "title": "B"}]}"#,
    #"{"remove": ["app.solo.only", "app.solo.only"]}"#,
  ])
  func `a use case is in a batch at most once`(json: String) {
    #expect(throws: UseCaseBatchError.self) {
      try plan(json)
    }
  }

  @Test
  func `the repeated use case is named`() {
    #expect(throws: UseCaseBatchError.repeated(identifier: "app.solo.only")) {
      try plan(
        #"{"remove": ["app.solo.only"], "save": [{"id": "app.solo.only", "title": "T"}]}"#,
      )
    }
  }

  @Test
  func `a removal of a use case that is not there refuses the batch`() {
    #expect(throws: UseCaseBatchError.editing(.unknown(identifier: "app.dark.nope"))) {
      try plan(
        """
        {"remove": ["app.dark.nope"], "save": [{"id": "app.dark.fine", "title": "Fine"}]}
        """,
      )
    }
  }

  @Test
  func `one use case with no group refuses the whole batch`() {
    #expect(throws: UseCaseBatchError.editing(.noGroup(identifier: "orphan"))) {
      try plan(
        """
        {"save": [{"id": "app.dark.fine", "title": "Fine"}, {"id": "orphan", "title": "T"}]}
        """,
      )
    }
  }
}
