import UseCasesCore

/// A cancellation that comes at the look the test names, and counts the looks.
actor CountingCancellation: CancellationObserving {
  private let raisedAt: Int
  private(set) var looks = 0

  /// Says no until the look number `raisedAt`, and yes from then on.
  init(raisedAt: Int) {
    self.raisedAt = raisedAt
  }

  func isCancelled() -> Bool {
    looks += 1

    return looks >= raisedAt
  }
}
