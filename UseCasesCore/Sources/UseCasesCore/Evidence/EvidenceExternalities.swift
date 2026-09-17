import Foundation

/// The clock the append path reads: `Date.now()` for the event id, `new Date()`
/// for `recorded_at`, and the lock's deadline and 25ms poll.
///
/// Both requirements are `async` so a test clock can be an actor — the
/// package's macOS 14 floor rules out `Synchronization.Mutex` — and so the
/// lock's wait suspends rather than blocking a thread of the cooperative pool.
public protocol EvidenceClock: Sendable {
  /// Milliseconds since the epoch, whole, as `Date.now()` answers.
  func now() async -> Double

  /// Wait about `milliseconds` before the lock is tried again.
  func sleep(milliseconds: Int) async
}

/// The random bytes the event id is built from (`crypto.randomBytes`).
public protocol EvidenceRandomSource: Sendable {
  func bytes(count: Int) -> [UInt8]
}

/// The real clock.
public struct SystemEvidenceClock: EvidenceClock {
  /// The process's own clock.
  public init() {}

  public func now() async -> Double {
    (Date().timeIntervalSince1970 * 1000).rounded(.down)
  }

  /// A suspension, not a blocked thread. Cancellation ends the wait early and
  /// the lock is simply tried again: the TypeScript has no cancellation.
  public func sleep(milliseconds: Int) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
  }
}

/// The system's cryptographically secure generator.
public struct SystemEvidenceRandomSource: EvidenceRandomSource {
  /// The process's own generator.
  public init() {}

  public func bytes(count: Int) -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    return (0 ..< count).map { _ in
      UInt8.random(in: .min ... .max, using: &generator)
    }
  }
}
