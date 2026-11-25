/// Waits for the process to be told to stop.
protocol ShutdownWatching: Sendable {
  /// Returns `true` once the process has been told to stop, and `false` when the waiting task is
  /// cancelled first.
  func waitsForShutdown() async -> Bool
}
