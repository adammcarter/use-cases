import Testing
@testable import UseCasesCore

struct ProposalChangeResolverTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  private static let toggle = #"{"id": "app.dark.toggle", "title": "Dark mode, changed"}"#
  private static let fresh = #"{"id": "app.refunds.partial", "title": "Refund part"}"#

  /// A proposal saving the use case, with more keys beside the batch when a test wants them.
  private static func saving(
    _ save: String,
    beside keys: String = "",
  ) -> String {
    "{\"title\": \"T\", \"save\": [" + save + "]" + keys + "}"
  }

  private func summary(_ json: String) throws -> [String] {
    try fixture.changes(json).map { change in
      "\(change.fit.rawValue) \(change.identifier)"
    }
  }

  @Test
  func `the use cases come in the order new, extends, changes, replaces, untouched`() throws {
    let order = try summary(
      """
      {"title": "T", "remove": ["app.solo.only"], "untouched": ["app.dark.other"],
       "save": [\(Self.toggle), \(Self.fresh),
                {"id": "app.pay.card.charge", "title": "Charge, extended"}],
       "fits": {"app.pay.card.charge": "extends"}}
      """,
    )

    #expect(order == [
      "new app.refunds.partial",
      "extends app.pay.card.charge",
      "changes app.dark.toggle",
      "replaces app.solo.only",
      "untouched app.dark.other",
    ])
  }

  @Test
  func `within a fit they come in the order the file lists them`() throws {
    let order = try summary(
      """
      {"title": "T", "remove": ["app.solo.only", "app.dark.other"],
       "untouched": ["app.pay.card.charge", "app.dark.toggle"]}
      """,
    )

    #expect(order == [
      "replaces app.solo.only",
      "replaces app.dark.other",
      "untouched app.pay.card.charge",
      "untouched app.dark.toggle",
    ])
  }

  @Test
  func `a save of a use case that exists changes it unless the proposal says extends`() throws {
    let plain = try fixture.changes(Self.saving(Self.toggle))
    let extended = try fixture.changes(
      Self.saving(Self.toggle, beside: #", "fits": {"app.dark.toggle": "extends"}"#),
    )

    #expect(plain.map(\.fit) == [.changes])
    #expect(extended.map(\.fit) == [.extends])
    #expect(plain.first?.before?.title == "Dark mode")
    #expect(plain.first?.shown.title == "Dark mode, changed")
  }

  @Test
  func `a save of a use case that does not exist is new`() throws {
    let changes = try fixture.changes(Self.saving(Self.fresh))

    #expect(changes.map(\.fit) == [.new])
    #expect(changes.first?.before == nil)
  }

  @Test
  func `a use case that goes or stays is shown as the workspace holds it`() throws {
    let changes = try fixture.changes(
      #"{"title": "T", "remove": ["app.solo.only"], "untouched": ["app.dark.other"]}"#,
    )

    #expect(changes.map(\.shown.title) == ["Dark mode", "Dark mode"])
    #expect(changes.map(\.before?.title) == ["Dark mode", "Dark mode"])
  }

  @Test(arguments: [
    #"{"title": "T", "remove": ["app.nope.x"]}"#,
    #"{"title": "T", "untouched": ["app.nope.x"], "remove": ["app.solo.only"]}"#,
  ])
  func `a use case that is not there cannot go or stay`(json: String) throws {
    #expect(try fixture.refusal(json) == .unknownUseCase(identifier: "app.nope.x"))
  }

  @Test(arguments: [
    #"{"title": "T", "remove": ["app.solo.only"], "untouched": ["app.solo.only"]}"#,
    #"""
    {"title": "T", "untouched": ["app.dark.toggle"],
     "save": [{"id": "app.dark.toggle", "title": "X"}]}
    """#,
  ])
  func `a use case in the batch is not untouched`(json: String) throws {
    let refused = try #require(try fixture.refusal(json))

    #expect(refused.message.contains("is in the batch, so it is not untouched"))
    #expect(refused.kind == .usage)
  }

  @Test(arguments: [
    (
      #"{"title": "T", "remove": ["app.solo.only"], "fits": {"app.solo.only": "extends"}}"#,
      "`fits` names 'app.solo.only', which the batch does not save",
    ),
    (
      #"{"title": "T", "remove": ["app.solo.only"], "you_see": {"app.dark.toggle": "x"}}"#,
      "`you_see` names 'app.dark.toggle', which the proposal neither saves, removes "
        + "nor leaves untouched",
    ),
    (
      #"{"title": "T", "remove": ["app.solo.only"], "golden": {"app.solo.only": ["s"]}}"#,
      "`golden` names 'app.solo.only', which the batch does not save",
    ),
    (
      #"""
      {"title": "T", "golden": {"app.dark.toggle": ["s", "nope"]},
       "save": [{"id": "app.dark.toggle", "title": "X",
                 "scenarios": [{"id": "s", "when": ["a"], "then": ["b"]}]}]}
      """#,
      "`golden` names scenario 'nope', which 'app.dark.toggle' does not have",
    ),
  ])
  func `a pointer at something the proposal does not hold is refused, never ignored`(
    json: String,
    message: String,
  ) throws {
    let refused = try #require(try fixture.refusal(json))

    #expect(refused.message.hasSuffix(message))
    #expect(refused.kind == .usage)
  }

  @Test
  func `what the person will see may be said of a use case that goes`() throws {
    let found = try fixture.changes(
      #"{"title": "T", "remove": ["app.solo.only"], "you_see": {"app.solo.only": "x"}}"#,
    )

    #expect(found.count == 1)
  }

  @Test
  func `what the person will see of an untouched use case is accepted`() throws {
    let found = try fixture.changes(
      """
      {"title": "T", "remove": ["app.solo.only"], "untouched": ["app.dark.other"],
       "you_see": {"app.dark.other": "y"}}
      """,
    )

    #expect(found.map(\.fit) == [.replaces, .untouched])
  }

  @Test
  func `fits on a use case that is new is refused, never ignored`() throws {
    let refused = try #require(
      try fixture.refusal(
        Self.saving(Self.fresh, beside: #", "fits": {"app.refunds.partial": "changes"}"#),
      ),
    )

    #expect(refused.kind == .usage)
    #expect(
      refused.message.hasSuffix(
        "`fits` names 'app.refunds.partial', which is new: its fit follows from the batch",
      ),
    )
  }

  @Test
  func `an applied proposal is held to the same pointers, without needing its removals`() throws {
    let resolver = ProposalChangeResolver()
    let applied = try fixture.proposal(
      """
      {"title": "T", "remove": ["app.gone.already"], "untouched": ["app.dark.other"],
       "save": [\(Self.toggle)], "you_see": {"app.dark.other": "y"}}
      """,
    )
    let pointingNowhere = try fixture.proposal(
      """
      {"title": "T", "remove": ["app.gone.already"], "untouched": ["app.dark.other"],
       "you_see": {"app.nope.x": "y"}}
      """,
    )
    let loaded = try fixture.batch.loaded()

    try resolver.checkReferences(of: applied, in: loaded)
    #expect(throws: LayoutRenderingError.self) {
      try resolver.checkReferences(of: pointingNowhere, in: loaded)
    }
  }
}
