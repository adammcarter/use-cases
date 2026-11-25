import Testing
@testable import UseCasesCore

struct ProposalBatchCheckerTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  private func refusal(_ json: String) throws -> LayoutRenderingError? {
    do {
      try ProposalBatchChecker().check(
        fixture.proposal(json),
        in: fixture.batch.loaded(),
      )

      return nil
    } catch let error as LayoutRenderingError {
      return error
    }
  }

  /// What the planner `apply` uses refuses the batch with; `nil` when it takes it.
  private func planRefusal(_ json: String) throws -> UseCaseBatchError? {
    let file = try fixture.proposal(json)

    do {
      _ = try UseCaseBatchPlanner().plan(
        file.batch,
        approvedBy: nil,
        in: fixture.batch.loaded(),
        links: [],
      )

      return nil
    } catch let error as UseCaseBatchError {
      return error
    }
  }

  @Test(arguments: [
    #"{"title": "T", "save": [{"id": "elsewhere.x.y", "title": "X"}]}"#,
    #"{"title": "T", "save": [{"id": "app.y", "title": "X"}]}"#,
    #"{"title": "T", "remove": ["app.nope.x"]}"#,
  ])
  func `a batch apply would refuse is refused with the planner's own refusal`(
    json: String,
  ) throws {
    let applyRefusal = try #require(try planRefusal(json))

    #expect(try refusal(json) == .batch(applyRefusal))
  }

  @Test
  func `a batch apply would take is let through`() throws {
    #expect(
      try refusal(
        #"{"title": "T", "save": [{"id": "app.refunds.partial", "title": "R"}]}"#,
      ) == nil,
    )
  }

  @Test
  func `a brief and a proposal refuse alike a file with an id apply refuses`() throws {
    let json = #"{"title": "T", "save": [{"id": "elsewhere.x.y", "title": "X"}]}"#

    #expect(throws: LayoutRenderingError.self) {
      try fixture.brief(json)
    }
    #expect(throws: LayoutRenderingError.self) {
      try fixture.proposalLayout(json)
    }
  }
}
