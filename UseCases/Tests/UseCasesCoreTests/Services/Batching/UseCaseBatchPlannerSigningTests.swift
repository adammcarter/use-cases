import Testing
@testable import UseCasesCore

/// A batch signed off: each use case it saves is approved as it now reads.
struct UseCaseBatchPlannerSigningTests {
  private let fixture: BatchFixture
  private let planner = UseCaseBatchPlanner(calendar: MockCalendarDay("2026-10-20"))
  private let kim: ApproverName

  init() throws {
    fixture = try BatchFixture()
    kim = try ApproverName(validating: "Kim")
  }

  private func plan(
    _ json: String,
    approvedBy approver: ApproverName? = nil,
  ) throws -> UseCaseBatchChange {
    try planner.plan(
      fixture.batch(json),
      approvedBy: approver,
      in: fixture.loaded(),
      links: [],
    )
  }

  private func steps(of change: UseCaseBatchChange) -> [String] {
    change.useCases.map { useCase in
      "\(useCase.action.rawValue) \(useCase.identifier)"
    }
  }

  @Test
  func `a signed-off batch approves each use case it saves, added or updated`() throws {
    let change = try plan(
      """
      {"save": [{"id": "app.dark.toggle", "title": "Toggle, changed"},
                {"id": "app.refunds.partial", "title": "Partial"}]}
      """,
      approvedBy: kim,
    )
    let after = try fixture.loadedAfter(change.writes)

    for identifier in ["app.dark.toggle", "app.refunds.partial"] {
      let approval = try #require(
        after.useCases.first { useCase in
          useCase.identifier.text == identifier
        }?.definition.approval,
      )

      #expect(approval.approver == "Kim")
      #expect(approval.day == "2026-10-20")
      #expect(approval.behaviour.count == 64)
    }

    let untouched = after.useCases.first { useCase in
      useCase.identifier.text == "app.dark.other"
    }

    #expect(untouched?.definition.approval == nil)
  }

  @Test
  func `a save otherwise unchanged writes the approval and is replaced`() throws {
    let change = try plan(
      fixture.savingAsShown("app.dark.toggle"),
      approvedBy: kim,
    )

    #expect(steps(of: change) == ["replaced app.dark.toggle"])
    #expect(change.writes.changes.map(\.path) == ["use-cases/dark.yml"])
  }

  @Test
  func `a use case already approved as it reads is left as it is, whoever signs the batch`(
  ) throws {
    let first = try plan(
      fixture.savingAsShown("app.dark.toggle"),
      approvedBy: kim,
    )
    _ = try fixture.loadedAfter(first.writes)

    let second = try planner.plan(
      fixture.batch(fixture.savingAsShown("app.dark.toggle")),
      approvedBy: ApproverName(validating: "Sam"),
      in: fixture.loaded(),
      links: [],
    )

    #expect(steps(of: second) == ["unchanged app.dark.toggle"])
    #expect(second.writes.isEmpty)
  }

  @Test
  func `without a signature a batch writes no approval and keeps the one a use case has`() throws {
    let signed = try plan(
      fixture.savingAsShown("app.dark.toggle"),
      approvedBy: kim,
    )
    _ = try fixture.loadedAfter(signed.writes)

    let change = try plan(
      #"{"save": [{"id": "app.dark.toggle", "title": "Retitled after approval"}]}"#,
    )
    let after = try fixture.loadedAfter(change.writes)
    let kept = after.useCases.first { useCase in
      useCase.identifier.text == "app.dark.toggle"
    }

    #expect(kept?.definition.approval?.approver == "Kim")
  }

  @Test
  func `a save that brings a sign-off of its own is refused, with or without a signature`(
  ) throws {
    let forged = """
    {"save": [{"id": "app.dark.toggle", "title": "T",
               "approved": {"by": "Someone", "on": "2026-01-01", "behaviour": "\(String(
                 repeating: "a",
                 count: 64,
               ))"}}]}
    """

    for approver in [nil, kim] {
      #expect(throws: UseCaseBatchError
        .editing(.approvalNotBySave(identifier: "app.dark.toggle")))
      {
        try plan(
          forged,
          approvedBy: approver,
        )
      }
    }
  }

  @Test
  func `the day of the sign-off is the one the calendar tells`() throws {
    let dated = UseCaseBatchPlanner(calendar: MockCalendarDay("2031-02-03"))
    let change = try dated.plan(
      fixture.batch(#"{"save": [{"id": "app.refunds.partial", "title": "Partial"}]}"#),
      approvedBy: kim,
      in: fixture.loaded(),
      links: [],
    )

    #expect(change.writes.changes.first?.text.contains("2031-02-03") == true)
  }

  @Test
  func `a promise that cannot be fingerprinted refuses the batch`() throws {
    let planner = UseCaseBatchPlanner(
      stamper: ApprovalStamper(
        fingerprinter: MockPromiseFingerprinting(failing: .missingIntent),
      ),
      calendar: MockCalendarDay(),
    )

    #expect(
      throws: UseCaseBatchError.stamping(
        .unfingerprintable(
          identifier: "app.refunds.partial",
          reason: "missingIntent",
        ),
      ),
    ) {
      try planner.plan(
        fixture.batch(#"{"save": [{"id": "app.refunds.partial", "title": "Partial"}]}"#),
        approvedBy: kim,
        in: fixture.loaded(),
        links: [],
      )
    }
  }
}
