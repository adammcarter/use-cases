/// Why scaffolding stopped with an error rather than a result.
public enum WorkspaceScaffoldError: Error, Equatable, Sendable {
  /// A hook target outside the repository, from a configured core.hooksPath.
  case pathEscape(PathError)
  /// A read, write, directory creation or chmod failed.
  case fileAccess(FileAccessError)

  public var code: String {
    switch self {
    case let .pathEscape(error): error.code
    case let .fileAccess(error): error.code
    }
  }

  public var message: String {
    switch self {
    case let .pathEscape(error): error.message
    case let .fileAccess(error): error.message
    }
  }
}
