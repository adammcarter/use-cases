/// How the tool server ended.
public enum ToolServerEnding: Equatable, Sendable {
  /// The host closed its input.
  case inputClosed

  /// The process was told to stop.
  case stopped
}
