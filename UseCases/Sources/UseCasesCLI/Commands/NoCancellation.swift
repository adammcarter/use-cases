import UseCasesCore

/// A request nobody cancels: what a command line is run with when no signal is watched.
struct NoCancellation: CancellationObserving {
  func isCancelled() async -> Bool {
    false
  }
}
