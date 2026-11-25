@testable import UseCasesCore

/// Who holds the signals, as a double: it holds none, notes each take and release, and says a
/// signal has come when it is told to.
actor SpySignalOwning: SignalOwning {
  /// What it was asked, in order: `take` or `release`.
  private(set) var events: [String] = []

  private let hasSignal: Bool

  init(hasSignal: Bool = false) {
    self.hasSignal = hasSignal
  }

  var isCancelled: Bool {
    hasSignal
  }

  func take() {
    events.append("take")
  }

  func release() {
    events.append("release")
  }
}
