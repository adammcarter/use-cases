/// Cancels when an observer the caller supplies says so. The observer is made when the job
/// begins, and nothing is given back when it ends: whoever supplied it owns it.
public actor ObservedCancellationScope: CancellationScoping {
  private let makeObserver: @Sendable () -> any CancellationObserving
  private var observer: (any CancellationObserving)?
  private var holders = 0
  private var isClaimed = false
  private var hasSeenCancellation = false

  /// - Parameter makeObserver: Called once, when the job begins.
  public init(makeObserver: @escaping @Sendable () -> any CancellationObserving) {
    self.makeObserver = makeObserver
  }

  public func begin() {
    if holders == 0 {
      observer = makeObserver()
    }

    holders += 1
  }

  public func end() {
    guard holders > 0 else {
      return
    }

    holders -= 1

    if holders == 0 {
      observer = nil
      isClaimed = false
    }
  }

  public func isCancelled() async -> Bool {
    guard let observer else {
      return false
    }

    let isCancelled = await observer.isCancelled()
    hasSeenCancellation = hasSeenCancellation || isCancelled

    return isCancelled
  }

  /// A request that was seen cancelled writes nothing from then on (see
  /// ``SignalCancellationScope/claimWrite()``).
  public func claimWrite() async -> Bool {
    guard await !isCancelled(), !hasSeenCancellation else {
      return false
    }

    isClaimed = true

    return true
  }

  public func isWriting() -> Bool {
    isClaimed
  }
}
