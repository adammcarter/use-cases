extension ProcessTermination {
  /// The run error this ending is, in the words of chapter 14 §11 and §12 and the acceptance
  /// suite. An exit code is not an error here (chapter 14 §13 judges it later) and a
  /// cancellation is not an error at all.
  var runErrorWords: String? {
    switch self {
    case let .signaled(signal):
      "command terminated abnormally (signal \(signal))"
    case let .timedOut(timeout):
      "command timed out after \(timeout.components.seconds) seconds"
    case .exited, .cancelled:
      nil
    }
  }
}
