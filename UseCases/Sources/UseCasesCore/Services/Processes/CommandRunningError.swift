/// Why a program could not be run at all (as against ending badly, which a ``CommandEnding``
/// says).
public enum CommandRunningError: Error, Equatable, Sendable {
  /// The program could not be started, or its output could not be kept, or it could not be
  /// waited for.
  case couldNotRun(reason: String)
}

extension CommandRunningError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .couldNotRun(reason):
      reason
    }
  }
}
