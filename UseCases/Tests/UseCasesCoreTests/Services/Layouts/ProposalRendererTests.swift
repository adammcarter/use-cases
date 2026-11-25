import Testing
@testable import UseCasesCore

struct ProposalRendererTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  private static let proposal = """
  {"title": "Dark mode, again", "remove": ["app.solo.only"], "untouched": ["app.dark.other"],
   "save": [{"id": "app.refunds.partial", "title": "Refund part", "value_tier": "critical"},
            {"id": "app.dark.toggle", "title": "Dark mode, retitled", "value_tier": "core"}],
   "you_see": {"app.dark.toggle": "a moon", "app.solo.only": "it is gone"},
   "decisions": [{"question": "how long", "options": ["a day", "a week"]}]}
  """

  @Test
  func `each use case is a line with its fit, its tier and what the person will see`() throws {
    let layout = try fixture.proposalLayout(Self.proposal)

    #expect(layout.title == "Dark mode, again")
    #expect(layout.changes == [
      ProposalChange(
        useCase: "app.refunds.partial",
        fit: .new,
        title: "Refund part",
        tier: "critical",
        youSee: nil,
      ),
      ProposalChange(
        useCase: "app.dark.toggle",
        fit: .changes,
        title: "Dark mode, retitled",
        tier: "core",
        youSee: "a moon",
      ),
      ProposalChange(
        useCase: "app.solo.only",
        fit: .replaces,
        title: "Dark mode",
        tier: "core",
        youSee: "it is gone",
      ),
      ProposalChange(
        useCase: "app.dark.other",
        fit: .untouched,
        title: "Dark mode",
        tier: "core",
        youSee: nil,
      ),
    ])
    #expect(layout.decisions == [ProposalDecision(
      question: "how long",
      options: ["a day", "a week"],
    )])
  }

  @Test
  func `who signs counts what changes or goes and never what stays`() throws {
    let layout = try fixture.proposalLayout(Self.proposal)

    #expect(layout.signOff == SignOffCounts(critical: 1, core: 2, supporting: 0))
  }

  @Test
  func `a use case with no tier is signed by the person, not by a tier`() throws {
    let layout = try fixture.proposalLayout(
      #"{"title": "T", "save": [{"id": "app.refunds.partial", "title": "R"}]}"#,
    )

    #expect(layout.signOff == SignOffCounts(critical: 0, core: 0, supporting: 0, untiered: 1))
    #expect(layout.changes.map(\.tier) == [nil])
  }

  @Test
  func `a use case with no tier counts as the person's, never dropped`() throws {
    let layout = try fixture.proposalLayout(
      """
      {"title": "T", "save": [
        {"id": "app.refunds.a", "title": "A"},
        {"id": "app.refunds.b", "title": "B", "value_tier": "core"},
        {"id": "app.refunds.c", "title": "C"}]}
      """,
    )

    #expect(layout.signOff == SignOffCounts(critical: 0, core: 1, supporting: 0, untiered: 2))
  }

  @Test
  func `supporting use cases are counted for the agent that may sign them`() throws {
    let layout = try fixture.proposalLayout(
      """
      {"title": "T", "save": [
        {"id": "app.refunds.a", "title": "A", "value_tier": "supporting"},
        {"id": "app.refunds.b", "title": "B", "value_tier": "supporting"}]}
      """,
    )

    #expect(layout.signOff == SignOffCounts(critical: 0, core: 0, supporting: 2))
  }
}
