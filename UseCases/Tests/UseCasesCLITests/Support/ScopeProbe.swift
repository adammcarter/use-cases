import UseCasesCore

/// A scope that never cancels and remembers when it was taken and given back, and what else the
/// test saw happen meanwhile, in order.
actor ScopeProbe: CancellationScoping {
  private(set) var events: [String] = []

  func record(_ event: String) {
    events.append(event)
  }

  func begin() {
    events.append("begin")
  }

  func end() {
    events.append("end")
  }

  func isCancelled() -> Bool {
    false
  }

  func claimWrite() -> Bool {
    events.append("claim")

    return true
  }

  func isWriting() -> Bool {
    false
  }
}
