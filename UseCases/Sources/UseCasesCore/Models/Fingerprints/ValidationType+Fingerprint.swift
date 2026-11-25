extension ValidationType {
  /// The `kind` the route payload writes (chapter 11 §89.4), as the authored spelling.
  var kindName: String {
    switch self {
    case .unit: "unit"
    case .integration: "integration"
    case .contract: "contract"
    case .snapshot: "snapshot"
    case .userInterface: "ui"
    case .e2e: "e2e"
    case .acceptance: "acceptance"
    case .performance: "performance"
    case .custom: "custom"
    }
  }
}
