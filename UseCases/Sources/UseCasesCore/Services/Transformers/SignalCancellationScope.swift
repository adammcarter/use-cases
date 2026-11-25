/// Cancels on SIGINT, SIGTERM and SIGHUP for as long as the job runs. The signals are taken over
/// when the job begins and given back when it ends, unless a scope that began earlier still holds
/// them, so a Ctrl-C after a job, while the command goes on to read or write, stops the command
/// as it would any other.
public actor SignalCancellationScope: CancellationScoping {
  private let ownership: any SignalOwning
  private var holders = 0
  private var isClaimed = false
  private var hasSeenCancellation = false

  /// Makes a scope that holds nothing until it begins.
  public init() {
    self.init(ownership: SignalOwnership.shared)
  }

  /// - Parameter ownership: Who holds the signals for the process, which the scopes share.
  init(ownership: any SignalOwning) {
    self.ownership = ownership
  }

  public func begin() async {
    holders += 1

    if holders == 1 {
      await ownership.take()
    }
  }

  public func end() async {
    guard holders > 0 else {
      return
    }

    holders -= 1

    if holders == 0 {
      isClaimed = false
      await ownership.release()
    }
  }

  public func isCancelled() async -> Bool {
    guard holders > 0 else {
      return false
    }

    let isCancelled = await ownership.isCancelled
    hasSeenCancellation = hasSeenCancellation || isCancelled

    return isCancelled
  }

  /// A request that was seen cancelled writes nothing from then on, even when the signals have
  /// been given back since: work that was answered as cancelled and left running claims nothing.
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
