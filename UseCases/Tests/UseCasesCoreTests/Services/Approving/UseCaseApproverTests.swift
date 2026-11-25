import Testing
@testable import UseCasesCore

struct UseCaseApproverTests {
  private let fixture: BatchFixture
  private let approver = UseCaseApprover(
    stamper: ApprovalStamper(),
    calendar: MockCalendarDay("2026-10-20"),
  )

  init() throws {
    fixture = try BatchFixture()
  }

  private func plan(
    _ identifiers: [String] = [],
    all: Bool = false,
    by name: String = "Kim",
  ) throws -> UseCaseApprovalChange {
    try approver.plan(
      approving: identifiers,
      all: all,
      by: name,
      in: fixture.loaded(),
    )
  }

  /// The sign-off of each use case of the workspace that has one.
  private func approvals(in workspace: LoadedWorkspace) -> [String: Approval] {
    var found: [String: Approval] = [:]

    for useCase in workspace.useCases {
      found[useCase.identifier.text] = useCase.definition.approval
    }

    return found
  }

  @Test
  func `a use case is approved with the name, the day and the fingerprint of its promise`(
  ) throws {
    let change = try plan(["app.dark.toggle"])
    let after = try fixture.loadedAfter(change.writes)
    let approval = try #require(approvals(in: after)["app.dark.toggle"])

    #expect(change.approver == "Kim")
    #expect(change.useCases == [
      ApprovedUseCase(
        identifier: "app.dark.toggle",
        file: "use-cases/dark.yml",
        action: .approved,
      ),
    ])
    #expect(approval.approver == "Kim")
    #expect(approval.day == "2026-10-20")
    #expect(approval.behaviour.count == 64)
    #expect(change.divergence(in: after) == nil)
  }

  @Test
  func `only the use cases asked for are approved`() throws {
    let after = try fixture.loadedAfter(plan(["app.dark.toggle"]).writes)

    #expect(approvals(in: after).keys.sorted() == ["app.dark.toggle"])
  }

  @Test
  func `use cases of one file all keep their sign-off`() throws {
    let change = try plan(["app.dark.toggle", "app.dark.other"])
    let after = try fixture.loadedAfter(change.writes)

    #expect(change.writes.changes.map(\.path) == ["use-cases/dark.yml"])
    #expect(approvals(in: after)["app.dark.toggle"] != nil)
    #expect(approvals(in: after)["app.dark.other"] != nil)
    #expect(change.divergence(in: after) == nil)
  }

  @Test
  func `a use case already approved as it reads is unchanged and writes nothing`() throws {
    _ = try fixture.loadedAfter(plan(["app.dark.toggle"]).writes)

    let again = try plan(
      ["app.dark.toggle"],
      by: "Sam",
    )

    #expect(again.useCases.map(\.action) == [.unchanged])
    #expect(again.writes.isEmpty)
    #expect(again.approver == "Sam")
  }

  @Test
  func `a promise that changed since it was approved is approved again`() throws {
    _ = try fixture.loadedAfter(plan(["app.dark.toggle"]).writes)
    let text = try #require(fixture.text(of: "use-cases/dark.yml"))
    try fixture.workspace.write(
      "use-cases/dark.yml",
      text.replacingOccurrences(of: "intent: Readable at night.", with: "intent: Readable."),
    )

    let again = try plan(
      ["app.dark.toggle"],
      by: "Sam",
    )

    #expect(again.useCases.map(\.action) == [.approved])
  }

  @Test
  func `everything is approved under all, drafts included, by id`() throws {
    try fixture.workspace.write(
      "use-cases/draft.yml",
      "prefix: draft\nuse_cases:\n  - id: sketch\n    title: A sketch\n",
    )

    let change = try plan(all: true)

    #expect(change.useCases.map(\.identifier) == [
      "app.dark.other", "app.dark.toggle", "app.draft.sketch", "app.pay.card.charge",
      "app.solo.only",
    ])
    #expect(change.useCases.allSatisfy { $0.action == .approved })
    #expect(change.writes.changes.map(\.path) == [
      "services/pay/use-cases/card.yml", "use-cases/dark.yml", "use-cases/draft.yml",
      "use-cases/solo.yml",
    ])
  }

  @Test
  func `use cases named are approved in the order named, each once`() throws {
    let change = try plan(["app.solo.only", "app.dark.toggle", "app.solo.only"])

    #expect(change.useCases.map(\.identifier) == ["app.solo.only", "app.dark.toggle"])
  }

  @Test
  func `use cases named together with all, or neither, are refused`() {
    #expect(throws: UseCaseApprovingError.namedAndAll) {
      try plan(["app.dark.toggle"], all: true)
    }
    #expect(throws: UseCaseApprovingError.nothingAsked) {
      try plan()
    }
  }

  @Test(arguments: ["app.dark.nope", "toggle", "app.dark", ""])
  func `only a full id of a use case that is there is approved`(identifier: String) {
    #expect(throws: UseCaseApprovingError.editing(.unknown(identifier: identifier))) {
      try plan([identifier])
    }
  }

  @Test(arguments: ["", " ", "\t"])
  func `a blank name is refused`(name: String) {
    #expect(
      throws: UseCaseApprovingError.approver(
        reason: "--by names who signed off, so it cannot be blank",
      ),
    ) {
      try plan(
        ["app.dark.toggle"],
        by: name,
      )
    }
  }

  @Test
  func `a name is trimmed and at most two hundred characters`() throws {
    #expect(try plan(["app.dark.toggle"], by: "  Kim  ").approver == "Kim")
    #expect(throws: UseCaseApprovingError.self) {
      try plan(
        ["app.dark.toggle"],
        by: String(repeating: "a", count: 201),
      )
    }
  }

  @Test
  func `nothing outside the approved field changes, comments and empty lists included`() throws {
    let before = """
    # kept
    prefix: noted
    use_cases:
      # about the item
      - id: item
        title: 'Item' # odd quoting
        value_tier: core
        # about the intent
        intent: "Readable."
        bindings: []
        out_of_scope: []

      - id: other
        title: Other

    """
    try fixture.workspace.write("use-cases/noted.yml", before)

    let change = try plan(["app.noted.item"])
    let text = try #require(change.writes.changes.first?.text)
    let after = text.components(separatedBy: "\n")
    let start = try #require(after.firstIndex(of: "    approved:"))
    var rest = after

    rest.removeSubrange(start ..< start + 4)

    #expect(rest == before.components(separatedBy: "\n"))
    #expect(change.warnings.isEmpty)
  }

  @Test
  func `a sign-off written again changes only the lines of the field`() throws {
    let file = "use-cases/noted.yml"
    try fixture.workspace.write(
      file,
      "prefix: noted\nuse_cases:\n  # keep me\n  - id: item\n    title: Item\n"
        + "    # and me\n    intent: Readable.\n    bindings: []\n",
    )
    _ = try fixture.loadedAfter(plan(["app.noted.item"]).writes)
    let signed = try #require(fixture.text(of: file))
    try fixture.workspace.write(
      file,
      signed.replacingOccurrences(of: "intent: Readable.", with: "intent: Readable at night."),
    )

    let again = try plan(
      ["app.noted.item"],
      by: "Sam",
    )
    let text = try #require(again.writes.changes.first?.text)
    let block = ["    approved:", "      by:", "      \"on\":", "      behaviour:"]

    func outside(_ text: String) -> [String] {
      text.components(separatedBy: "\n").filter { line in
        !block.contains { prefix in line.hasPrefix(prefix) }
      }
    }

    #expect(again.useCases.map(\.action) == [.approved])
    #expect(try outside(text) == outside(#require(fixture.text(of: file))))
    #expect(text.contains("by: Sam\n"))
    #expect(!text.contains("by: Kim"))
  }

  @Test
  func `only a comment inside a field that is written again is dropped, and listed`() throws {
    try fixture.workspace.write(
      "use-cases/noted.yml",
      "prefix: noted\nuse_cases:\n  - id: item\n    # about the title\n    title: Item\n"
        + "    approved:\n      # who\n      by: Sam\n      \"on\": \"2026-01-01\"\n"
        + "      behaviour: \"\(String(repeating: "0", count: 64))\"\n",
    )

    let change = try plan(["app.noted.item"])
    let text = try #require(change.writes.changes.first?.text)

    #expect(change.warnings.count == 1)
    #expect(change.warnings.first?.contains("# who") == true)
    #expect(text.contains("# about the title"))
    #expect(!text.contains("# who"))
  }

  @Test
  func `a fingerprint that looks like a number is still read back as text`() throws {
    let numeric = String(repeating: "1", count: 30) + "e" + String(repeating: "5", count: 33)
    let approver = UseCaseApprover(
      stamper: ApprovalStamper(fingerprinter: MockPromiseFingerprinting(answering: numeric)),
      calendar: MockCalendarDay(),
    )

    let change = try approver.plan(
      approving: ["app.dark.toggle"],
      all: false,
      by: "Kim",
      in: fixture.loaded(),
    )
    let after = try fixture.loadedAfter(change.writes)

    #expect(approvals(in: after)["app.dark.toggle"]?.behaviour == numeric)
  }

  @Test
  func `a promise that cannot be fingerprinted refuses the sign-off`() {
    let approver = UseCaseApprover(
      stamper: ApprovalStamper(fingerprinter: MockPromiseFingerprinting(failing: .missingIntent)),
      calendar: MockCalendarDay(),
    )

    #expect(throws: UseCaseApprovingError.self) {
      try approver.plan(
        approving: ["app.dark.toggle"],
        all: false,
        by: "Kim",
        in: fixture.loaded(),
      )
    }
  }

  @Test
  func `each sign-off is asked of the run of edits, in id order`(
  ) throws {
    let approver = UseCaseApprover(
      stamper: ApprovalStamper(),
      calendar: MockCalendarDay(),
      sequences: MockEditSequenceMaking(writes: WritePlan(changes: [])),
    )

    let change = try approver.plan(
      approving: [],
      all: true,
      by: "Kim",
      in: fixture.loaded(),
    )

    #expect(change.warnings == [
      "approving app.dark.other", "approving app.dark.toggle", "approving app.pay.card.charge",
      "approving app.solo.only",
    ])
  }
}
