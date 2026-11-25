/// Why a workspace did not load (chapter 09 §26).
public enum WorkspaceLoadingError: Error, Equatable, Sendable {
  /// No folder could be named as the workspace root.
  case noWorkspace(message: String)

  /// The workspace is INVALID. Each problem is one line, `<file>:<line>: <message>` or
  /// `<file>: <message>`, in the order of chapter 09 §27.1.
  case invalid(problems: [String])

  /// The schemas that ship inside this build could not be loaded, so nothing could be checked.
  case schemasUnavailable(message: String)

  /// The refusal as the text a person reads: one line per problem.
  public var message: String {
    switch self {
    case let .noWorkspace(message), let .schemasUnavailable(message):
      message
    case let .invalid(problems):
      problems.joined(separator: "\n")
    }
  }
}
