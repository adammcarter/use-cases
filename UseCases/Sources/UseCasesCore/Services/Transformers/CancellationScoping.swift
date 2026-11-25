/// The cancellation of one job that starts processes: observing begins when the first process is
/// about to start and ends when the job is over, so that a request that starts nothing takes over
/// nothing, and a signal that arrives after the job is not swallowed by a flag no one reads
/// (chapter 14 §14).
///
/// A scope also tells a request that writes from one that is still getting ready to: a request
/// stopped before its write begins writes nothing, and one stopped after finishes the write
/// (chapter 13 §15).
public protocol CancellationScoping: CancellationObserving {
  /// Starts observing. Called once, before the first process starts. Scopes nest: observing
  /// ends with the last `end`.
  func begin() async

  /// Stops observing and gives back what `begin` took over.
  func end() async

  /// Claims the right to write, just before the first byte. Returns `false`, and claims nothing,
  /// when the request was already cancelled: it writes nothing. After a claim the request goes
  /// on to the end of its write whatever arrives.
  func claimWrite() async -> Bool

  /// Whether a write has been claimed, which a caller that would abandon a cancelled request
  /// must not do.
  func isWriting() async -> Bool
}
