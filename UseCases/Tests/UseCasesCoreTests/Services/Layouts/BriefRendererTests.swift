import Testing
@testable import UseCasesCore

struct BriefRendererTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  private static let discounts = """
  {"id": "app.dark.toggle", "title": "Dark mode, retitled", "value_tier": "critical",
   "intent": "Dark mode follows the system.",
   "scenarios": [
     {"id": "follows", "given": ["The system is dark."], "when": ["The app opens."],
      "then": ["It is dark."]},
     {"id": "manual", "when": ["The person picks light."], "then": ["It is light."]}],
   "out_of_scope": ["Scheduled switching."],
   "validation": [
     {"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["follows"]},
     {"id": "again", "type": {"kind": "unit"}, "covers": ["manual"]},
     {"id": "ui", "type": {"kind": "ui"}, "covers": ["manual"]}]}
  """

  /// A proposal saving the use case above, with more keys beside the batch when a test wants them.
  private static func proposal(beside keys: String = "") -> String {
    "{\"title\": \"T\", \"save\": [" + discounts + "]" + keys + "}"
  }

  private func cards(_ json: String) throws -> [BriefCard] {
    try fixture.brief(json).cards
  }

  @Test
  func `a card for each use case that is added, changed or removed, and none for the untouched`(
  ) throws {
    let found = try cards(
      """
      {"title": "T", "remove": ["app.solo.only"], "untouched": ["app.dark.other"],
       "save": [\(Self.discounts), {"id": "app.refunds.partial", "title": "Refund part"}]}
      """,
    )

    #expect(found.map(\.useCase) == ["app.refunds.partial", "app.dark.toggle", "app.solo.only"])
    #expect(found.map(\.fit) == [.new, .changes, .replaces])
  }

  @Test
  func `a changed card says what it promises now, what it promised before, and how it is proven`(
  ) throws {
    let card = try #require(
      try cards(Self.proposal()).first,
    )

    #expect(card.title == "Dark mode, retitled")
    #expect(card.tier == "critical")
    #expect(card.now == "Dark mode follows the system.")
    #expect(card.was == "Readable at night.")
    #expect(card.notIncluded == ["Scheduled switching."])
    #expect(card.provenBy == ["unit tests", "UI tests"])
  }

  @Test
  func `a scenario is one line, and the first is the golden path unless the proposal says`(
  ) throws {
    let plain = try #require(try cards(Self.proposal()).first)
    let named = try #require(
      try cards(
        Self.proposal(beside: #", "golden": {"app.dark.toggle": ["manual"]}"#),
      ).first,
    )

    #expect(plain.scenarios == [
      BriefScenario(isGolden: true, text: "given The system is dark: The app opens → It is dark"),
      BriefScenario(isGolden: false, text: "The person picks light → It is light"),
    ])
    #expect(named.scenarios.map(\.isGolden) == [false, true])
  }

  @Test
  func `an acceptance route performed by a procedure is told by its first step`() throws {
    let card = try #require(
      try cards(
        """
        {"title": "T", "save": [{"id": "app.dark.toggle", "title": "T",
          "scenarios": [{"id": "s", "when": ["a"], "then": ["b"]}],
          "validation": [
            {"id": "one", "type": {"kind": "acceptance"}, "covers": ["s"],
             "procedure": {"steps": ["Open the settings.", "Switch it."]}},
            {"id": "two", "type": {"kind": "acceptance"}, "covers": ["s"],
             "procedure": {"steps": ["Open the settings..."]}},
            {"id": "three", "type": {"kind": "acceptance"}, "covers": ["s"],
             "procedure": {"steps": ["Open the settings."]}},
            {"id": "four", "type": {"kind": "unit"}, "covers": ["s"]}]}]}
        """,
      ).first,
    )

    #expect(card.provenBy == [
      "trying it: Open the settings",
      "unit tests",
    ])
  }

  @Test
  func `a route that does not gate verification is kept out of proven by`() throws {
    let card = try #require(
      try cards(
        """
        {"title": "T", "save": [{"id": "app.dark.toggle", "title": "T",
          "scenarios": [{"id": "s", "when": ["a"], "then": ["b"]}],
          "validation": [
            {"id": "one", "type": {"kind": "unit"}, "covers": ["s"]},
            {"id": "two", "type": {"kind": "e2e"}, "covers": ["s"], "gates_verification": false}]}]}
        """,
      ).first,
    )

    #expect(card.provenBy == ["unit tests"])
  }

  @Test
  func `a golden path that names no scenario leaves every scenario an edge`() throws {
    let card = try #require(
      try cards(
        Self.proposal(beside: #", "golden": {"app.dark.toggle": []}"#),
      ).first,
    )

    #expect(card.scenarios.map(\.isGolden) == [false, false])
  }

  @Test
  func `a card has no was when the intent is the same`() throws {
    let card = try #require(
      try cards(
        """
        {"title": "T", "save": [{"id": "app.dark.toggle", "title": "Retitled",
                                  "intent": "Readable at night."}]}
        """,
      ).first,
    )

    #expect(card.was == nil)
    #expect(card.now == "Readable at night.")
  }

  @Test
  func `a use case with no words is told as not written yet, and so is what it was`() throws {
    let found = try cards(
      """
      {"title": "T", "save": [{"id": "app.refunds.partial", "title": "Refund part"},
                              {"id": "app.dark.toggle", "title": "Dark mode", "intent": "  "}]}
      """,
    )

    #expect(found.map(\.now) == ["Not written yet.", "Not written yet."])
    #expect(found.map(\.was) == [nil, "Readable at night."])
  }

  @Test
  func `a removed card shows only what goes, from its intent`() throws {
    let card = try #require(
      try cards(#"{"title": "T", "remove": ["app.solo.only"]}"#).first,
    )

    #expect(card.fit == .replaces)
    #expect(card.now == "Removed.")
    #expect(card.was == "Readable at night.")
    #expect(card.scenarios.isEmpty)
    #expect(card.notIncluded.isEmpty)
    #expect(card.provenBy.isEmpty)
    #expect(card.tier == "core")
  }

  @Test
  func `a card is for the use case as the proposal leaves it, with no tier when it has none`(
  ) throws {
    let card = try #require(
      try cards(#"{"title": "T", "save": [{"id": "app.refunds.partial", "title": "R"}]}"#).first,
    )

    #expect(card.tier == nil)
    #expect(card.scenarios.isEmpty)
  }
}
