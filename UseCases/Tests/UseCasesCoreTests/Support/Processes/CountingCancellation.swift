import UseCasesTestSupport
@testable import UseCasesCore

/// A cancellation that is never raised, and opens `askedTwice` the second time it is asked.
actor CountingCancellation: CancellationObserving {
  let askedTwice = UseCasesTestSupport.Gate()

  private var count = 0

  func isCancelled() async -> Bool {
    count += 1

    if count == 2 {
      await askedTwice.open()
    }

    return false
  }
}
