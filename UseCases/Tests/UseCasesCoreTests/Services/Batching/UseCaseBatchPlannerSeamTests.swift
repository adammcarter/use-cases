import Testing
@testable import UseCasesCore

/// The batch planner asked through the seams it is given.
struct UseCaseBatchPlannerSeamTests {
  private let fixture: BatchFixture

  init() throws {
    fixture = try BatchFixture()
  }

  @Test
  func `the edits are asked for in the order the batch runs, whatever order it is written in`()
    throws
  {
    let planner = UseCaseBatchPlanner(
      calendar: MockCalendarDay(),
      sequences: MockEditSequenceMaking(writes: WritePlan(changes: [])),
      warner: MockStillMarkedWarning(),
    )

    let change = try planner.plan(
      fixture.batch(
        """
        {"save": [{"id": "app.dark.toggle", "title": "A"},
                  {"id": "app.refunds.partial", "title": "B"},
                  {"id": "app.dark.other", "title": "C"},
                  {"id": "app.refunds.full", "title": "D"}],
         "remove": ["app.solo.only", "app.pay.card.charge"]}
        """,
      ),
      approvedBy: nil,
      in: fixture.loaded(),
      links: [],
    )

    #expect(change.warnings == [
      "marked: app.solo.only, app.pay.card.charge in 0 links",
      "removing app.solo.only",
      "removing app.pay.card.charge",
      "adding app.refunds.partial",
      "adding app.refunds.full",
      "replacing app.dark.toggle",
      "replacing app.dark.other",
    ])
  }

  @Test
  func `the files to write are the ones the run of edits ends with`() throws {
    let writes = try WritePlan.making([.create("use-cases/mine.yml", "x")])
    let planner = UseCaseBatchPlanner(
      calendar: MockCalendarDay(),
      sequences: MockEditSequenceMaking(writes: writes),
    )

    let change = try planner.plan(
      fixture.batch(#"{"remove": ["app.solo.only"]}"#),
      approvedBy: nil,
      in: fixture.loaded(),
      links: [],
    )

    #expect(change.writes == writes)
  }
}
