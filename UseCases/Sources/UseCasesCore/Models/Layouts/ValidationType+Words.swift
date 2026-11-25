extension ValidationType {
  /// How a route of this kind is told to a person under PROVEN BY.
  var words: String {
    switch self {
    case .unit:
      "unit tests"
    case .integration:
      "integration tests"
    case .contract:
      "contract tests"
    case .snapshot:
      "snapshot tests"
    case .userInterface:
      "UI tests"
    case .e2e:
      "end-to-end tests"
    case .acceptance:
      "trying it"
    case .performance:
      "performance checks"
    case let .custom(name):
      name.text
    }
  }
}
