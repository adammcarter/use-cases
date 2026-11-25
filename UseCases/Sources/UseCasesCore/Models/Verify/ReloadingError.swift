/// Why a workspace could not be read again at the finish point (chapter 13 §7 step 6).
public enum ReloadingError: Error, Equatable, Sendable {
  /// The workspace is INVALID now. Each problem is one line.
  case invalid(problems: [String])

  /// The request was cancelled while the workspace was read.
  case cancelled
}
