/// Why the tool server could not be run.
public enum ToolServerError: Error, Equatable, Sendable {
  /// The catalogue of tools could not be made, for this reason.
  case catalogue(reason: String)

  /// The server could not start on its transport, for this reason.
  case transport(reason: String)

  /// The lifeline the commands hang by could not be made, for this reason.
  case lifeline(reason: String)
}

extension ToolServerError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .catalogue(reason):
      "the tools could not be made: \(reason)"
    case let .transport(reason):
      "the server could not start: \(reason)"
    case let .lifeline(reason):
      "the server could not make the lifeline of its commands: \(reason)"
    }
  }
}
