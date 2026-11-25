/// How serving tools ended.
public enum ToolServingEnding: Equatable, Sendable {
  /// The host closed its input, and every call still running was stopped.
  case inputClosed

  /// The process was told to stop (SIGINT, SIGTERM or SIGHUP), and every call still running was
  /// stopped.
  case stopped

  /// The server could not be run at all, for this reason.
  case failed(reason: String)
}
