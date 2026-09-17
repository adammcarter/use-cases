import Foundation

/// The source of `Date.now()`, which names a run's idempotency key when the
/// caller gave none.
public protocol CapsuleClock: Sendable {
  /// Milliseconds since the epoch, whole, as `Date.now()` answers.
  func now() -> Double
}

/// The process's own clock.
public struct SystemCapsuleClock: CapsuleClock {
  /// Reads the system time.
  public init() {}

  public func now() -> Double {
    (Date().timeIntervalSince1970 * 1000).rounded(.down)
  }
}
