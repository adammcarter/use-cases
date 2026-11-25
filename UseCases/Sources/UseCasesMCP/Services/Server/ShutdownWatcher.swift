import UseCasesCore

/// Looks at the cancellation observer on the clock, since a signal handler can only set a flag
/// (chapter 14 §14).
struct ShutdownWatcher: ShutdownWatching {
  private let observer: any CancellationObserving
  private let clock: any Clock<Duration>
  private let pollInterval: Duration

  /// - Parameters:
  ///   - observer: Says when SIGINT, SIGTERM or SIGHUP has come.
  ///   - clock: Times the looking.
  ///   - pollInterval: How often to look.
  init(
    observer: any CancellationObserving,
    clock: any Clock<Duration> = ContinuousClock(),
    pollInterval: Duration = .milliseconds(100),
  ) {
    self.observer = observer
    self.clock = clock
    self.pollInterval = pollInterval
  }

  func waitsForShutdown() async -> Bool {
    while !Task.isCancelled {
      if await observer.isCancelled() {
        return true
      }

      do {
        try await clock.sleep(for: pollInterval)
      } catch {
        return false
      }
    }

    return false
  }
}
