/// Why the hooks of a clone could not be looked at (chapter 18 §4, §6).
public enum HooksError: Error, Equatable, Sendable {
  /// The folder is not in a git repository, so there are no hooks to look at.
  case notAGitRepository(folder: String)

  /// git could not be run, or did not answer.
  case gitUnavailable(reason: String)

  /// A hook file or the hooks folder cannot be read.
  case unreadable(
    path: String,
    reason: String,
  )

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .notAGitRepository(folder):
      "not a git repository: hooks live in git, and '\(folder)' is not in a git repository"
    case let .gitUnavailable(reason):
      "git cannot be run, so the hooks cannot be looked at: \(reason)"
    case let .unreadable(path, reason):
      "\(path) cannot be read: \(reason)"
    }
  }
}
