/// How a supervised command ended (chapter 14 §11, §12, §14).
enum ProcessTermination: Equatable, Sendable {
  /// The command ended by itself with this exit code.
  case exited(Int32)

  /// A signal killed the command, whichever signal it was.
  case signaled(Int32)

  /// The command was still running when its time ran out, and its whole group was stopped.
  case timedOut(after: Duration)

  /// A cancellation arrived, and the command's whole group was stopped (or never started).
  case cancelled
}
