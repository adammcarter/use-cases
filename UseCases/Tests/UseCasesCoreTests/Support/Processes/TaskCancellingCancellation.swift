@testable import UseCasesCore

/// Never says the run is cancelled; once armed, it cancels the task that next asks it, as a
/// caller cancelling the run's task while it waits would, so the watcher next finds its sleep
/// cancelled.
actor TaskCancellingCancellation: CancellationObserving {
  private var isArmed = false

  func arm() {
    isArmed = true
  }

  func isCancelled() async -> Bool {
    if isArmed {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    return false
  }
}
