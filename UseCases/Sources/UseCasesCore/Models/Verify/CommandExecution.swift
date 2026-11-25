/// How running one validation's command came out (chapter 14).
enum CommandExecution: Equatable, Sendable {
  /// The command ended, or could not be run at all; either way it has its own result.
  case ran(RanCommand)

  /// The request was cancelled and the command, if it had started, was stopped.
  case cancelled
}
