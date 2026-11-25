/// Why `prune` could not plan (chapter 12 §24, §31).
public enum StorePruningError: Error, Equatable, Sendable {
  /// Fingerprinting found the workspace INVALID, so what status uses cannot be known and nothing
  /// is pruned. Each problem is one line, in report order.
  case invalidWorkspace(problems: [String])

  /// The store could not be read safely: every problem, as a person reads it. A damaged store is
  /// never pruned around.
  case unreadable(problems: [String])

  /// What a person is told.
  public var message: String {
    switch self {
    case let .invalidWorkspace(problems):
      problems.joined(separator: "\n")
    case let .unreadable(problems):
      "the results store cannot be read, so nothing was pruned: "
        + problems.joined(separator: "; ")
    }
  }
}
