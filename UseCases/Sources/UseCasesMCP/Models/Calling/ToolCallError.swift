/// Why a tool call has no result to give. Anything else a call can go wrong in is a result, marked
/// as a tool error (chapter 20 §4): only a call that is not a call of any tool is a protocol
/// error.
enum ToolCallError: Error, Equatable {
  /// No such tool.
  case unknownTool(String)

  /// The call was cancelled, and the command it ran was stopped. A cancelled request is not
  /// answered (the protocol's cancellation).
  case cancelled
}
