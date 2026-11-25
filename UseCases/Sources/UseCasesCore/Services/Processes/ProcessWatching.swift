import Foundation

/// Watches one started command until it ends, its time is up, or a cancellation arrives
/// (chapter 14 §11, §14).
protocol ProcessWatching: Sendable {
  /// Watches the command until it ends, its time is up (counted from now; `nil` means it has no
  /// limit), or a cancellation arrives; the last two stop its whole group.
  func watch(
    leader: pid_t,
    timeout: Duration?,
  ) async throws(ProcessSupervisingError) -> ProcessTermination

  /// Whether the run was cancelled.
  func isCancelled() async -> Bool
}
