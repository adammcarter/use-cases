/// Failures that stop a matrix load or mutation outright, rather than becoming
/// a diagnostic. Every one is a filesystem call failing: the TypeScript lets
/// node's error escape, and the CLI reports its `code` and `message`.
public enum UseCaseMatrixError: Error, Equatable, Sendable {
  /// A directory could not be listed, an entry could not be inspected, or a
  /// mutated file could not be read or written.
  case fileAccess(FileAccessError)

  /// node's error code, e.g. `ENOTDIR` or `EACCES`.
  public var code: String {
    switch self {
    case let .fileAccess(error):
      error.code
    }
  }

  /// node's message, e.g. `ENOTDIR: not a directory, scandir '<path>'`.
  public var message: String {
    switch self {
    case let .fileAccess(error):
      error.message
    }
  }
}
