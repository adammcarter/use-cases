@testable import UseCasesMCP

/// A watcher that says the process is told to stop when the test says so, and says it never was
/// if the task waiting on it is cancelled first.
struct MockShutdownWatching: ShutdownWatching {
  private let signals: AsyncStream<Void>
  private let signal: AsyncStream<Void>.Continuation

  init() {
    (signals, signal) = AsyncStream.makeStream(of: Void.self)
  }

  /// Tells the watcher the process was told to stop.
  func stop() {
    signal.yield()
  }

  func waitsForShutdown() async -> Bool {
    // Iterating ends when the task is cancelled, with nothing to say.
    for await _ in signals {
      return true
    }

    return false
  }
}
