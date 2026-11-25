/// A cancellation that never comes: what a run is given when only its task can be cancelled.
struct NeverCancelled: CancellationObserving {
  func isCancelled() async -> Bool {
    false
  }
}
