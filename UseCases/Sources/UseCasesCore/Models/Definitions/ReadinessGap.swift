/// One thing a DRAFT use case lacks before it is READY (chapter 02 "READY").
enum ReadinessGap: Equatable, Sendable {
  case valueTier
  case intent

  /// There is no scenario.
  case scenarios

  /// There is no validation route.
  case validation

  /// No gating route covers this scenario.
  case uncoveredScenario(ScenarioIdentifier)

  /// The words that name the gap where the acceptance tests fix them (`value_tier`, `intent`,
  /// `a gating route covering scenario <id>`); nil where no chapter or test does.
  var pinnedText: String? {
    switch self {
    case .valueTier:
      "value_tier"
    case .intent:
      "intent"
    case let .uncoveredScenario(identifier):
      "a gating route covering scenario \(identifier.text)"
    case .scenarios, .validation:
      nil
    }
  }
}
