extension ReadinessGap {
  /// The gap as a person is told it: the pinned words where there are some, and plain words for
  /// the two that no test pins.
  var words: String {
    switch self {
    case .scenarios:
      "a scenario"
    case .validation:
      "a validation route"
    case .valueTier, .intent, .uncoveredScenario:
      pinnedText ?? ""
    }
  }
}
