/// How a program run through ``CommandRunning`` ended.
public enum CommandEnding: Equatable, Sendable {
  /// It ended by itself with this exit code.
  case exited(Int32)

  /// A signal killed it, whichever signal it was.
  case signaled(Int32)

  /// The caller's task was cancelled, and the program's whole group was stopped (or never
  /// started).
  case cancelled
}
