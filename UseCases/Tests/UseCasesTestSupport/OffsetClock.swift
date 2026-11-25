import Atomics

/// The system's monotonic clock, moved on by jumps the test makes when something it can see has
/// happened: for the few tests of a real process that need a time limit or a grace to run out at
/// a chosen moment, and never by the passing of time.
///
/// A task already asleep on it sees a jump when it next wakes and reads `now`; code that looks
/// at the clock between short sleeps sees it at its next look.
public final class OffsetClock: Clock, Sendable {
  public typealias Instant = ContinuousClock.Instant

  private let base = ContinuousClock()
  /// The jumps made so far, in nanoseconds.
  private let offset = ManagedAtomic<Int64>(0)

  public init() {}

  public var now: Instant {
    base.now.advanced(by: .nanoseconds(offset.load(ordering: .acquiring)))
  }

  public var minimumResolution: Duration {
    base.minimumResolution
  }

  /// Moves every later reading of `now` on by `duration`.
  public func jump(by duration: Duration) {
    offset.wrappingIncrement(
      by: duration.wholeNanoseconds,
      ordering: .acquiringAndReleasing,
    )
  }

  public func sleep(
    until deadline: Instant,
    tolerance: Duration? = nil,
  ) async throws {
    // Waits as long as is left on this clock, on the real one.
    try await base.sleep(
      until: base.now.advanced(by: now.duration(to: deadline)),
      tolerance: tolerance,
    )
  }
}
