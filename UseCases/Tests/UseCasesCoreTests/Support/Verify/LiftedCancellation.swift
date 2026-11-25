import UseCasesCore
import UseCasesTestSupport

/// A cancellation that is raised and can then be lifted again, as a signal flag is cleared
/// between requests: cancelled while `raised` is raised and `lifted` is not.
struct LiftedCancellation: CancellationObserving {
  let raised: CancellationSwitch
  let lifted: CancellationSwitch

  func isCancelled() async -> Bool {
    guard await raised.isCancelled() else {
      return false
    }

    return await !lifted.isCancelled()
  }
}
