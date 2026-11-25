import Foundation

/// Stops a command and everything it started (chapter 14 §11).
protocol ProcessGroupStopping: Sendable {
  /// Returns once the group of `leader` is gone, or once it has been asked, and then forced, and
  /// is still there. A group that cannot be waited for is not a reason to throw: the supervisor
  /// has nothing more it could do.
  func stop(leader: pid_t) async
}
