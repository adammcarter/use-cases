/// The two hooks Use Cases can add to a clone (chapter 18 §2), in the fixed order every list of
/// them is written in.
public enum HookName: String, CaseIterable, Equatable, Sendable {
  case commit
  case push

  /// The git moment the hook runs at, which is also the name of its file.
  public var event: String {
    switch self {
    case .commit:
      "pre-commit"
    case .push:
      "pre-push"
    }
  }

  /// What the hook runs, as a person reads it.
  public var runs: String {
    switch self {
    case .commit:
      "use-cases validate"
    case .push:
      "use-cases status --gate"
    }
  }

  /// The command the hook runs after `use-cases --workspace <folder>`.
  var arguments: String {
    switch self {
    case .commit:
      "validate --quiet"
    case .push:
      "status --gate --quiet"
    }
  }
}
