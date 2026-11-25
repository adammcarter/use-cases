extension BriefCard {
  /// The text of a card for a use case that has no intent to show.
  static let unwritten = "Not written yet."

  /// The text of the card of a use case that goes.
  static let removed = "Removed."

  /// The card of a change that adds, extends, changes or removes a use case.
  ///
  /// - Parameters:
  ///   - change: A change that is not untouched.
  ///   - golden: The ids of the scenarios that are the golden path; the first scenario when the
  ///     proposal says nothing.
  init(
    change: ResolvedChange,
    golden: [String]?,
  ) {
    let shown = change.shown
    let tier = shown.valueTier?.rawValue

    guard change.fit != .replaces else {
      self.init(
        useCase: change.identifier,
        fit: change.fit,
        title: shown.title,
        tier: tier,
        now: Self.removed,
        was: Self.written(shown.intent) ?? shown.title,
        scenarios: [],
        notIncluded: [],
        provenBy: [],
      )

      return
    }

    let firsts = golden ?? shown.scenarios.prefix(1).map(\.identifier.text)

    self.init(
      useCase: change.identifier,
      fit: change.fit,
      title: shown.title,
      tier: tier,
      now: Self.written(shown.intent) ?? Self.unwritten,
      was: Self.was(of: change),
      scenarios: shown.scenarios.map { scenario in
        BriefScenario(
          isGolden: firsts.contains(scenario.identifier.text),
          text: scenario.line,
        )
      },
      notIncluded: shown.outOfScope,
      provenBy: shown.provenBy,
    )
  }

  /// What the use case promised before, when its intent is not the same now.
  private static func was(of change: ResolvedChange) -> String? {
    guard let before = change.before, before.intent != change.shown.intent else {
      return nil
    }

    return written(before.intent) ?? unwritten
  }

  /// The intent, when it has words in it.
  private static func written(_ intent: String?) -> String? {
    guard let intent, !intent.isWhitespaceOnly else {
      return nil
    }

    return intent
  }
}
