import Atomics

/// A clock whose time moves only when the test moves it, so no test waits on the passing of time.
///
/// A task that sleeps on it parks until the test advances the clock past its deadline. The test
/// learns that a task has parked from `nextSleep()`, an event, and never by guessing.
public final class TestClock: Clock, Sendable {
  /// A reading of a `TestClock`: how far it had been advanced from its start.
  public struct Instant: InstantProtocol, Sendable {
    public let offset: Duration

    public init(offset: Duration) {
      self.offset = offset
    }

    public static func < (
      lhs: Instant,
      rhs: Instant,
    ) -> Bool {
      lhs.offset < rhs.offset
    }

    public func advanced(by duration: Duration) -> Instant {
      Instant(offset: offset + duration)
    }

    public func duration(to other: Instant) -> Duration {
      other.offset - offset
    }
  }

  private let tickets = ManagedAtomic<Int>(0)
  private let sleepers = TestClockSleepers()

  public init() {}

  public var now: Instant {
    Instant(offset: .nanoseconds(sleepers.elapsed.load(ordering: .acquiring)))
  }

  public var minimumResolution: Duration {
    .nanoseconds(1)
  }

  /// Parks until the clock is advanced to `deadline`. A deadline the clock has already reached,
  /// as with a sleep of zero or less, returns at once and parks nothing. Throws
  /// `CancellationError` when the task is cancelled, whether before it parks or while parked,
  /// and whether the cancel or an advance reaches the clock first.
  public func sleep(
    until deadline: Instant,
    tolerance _: Duration? = nil,
  ) async throws {
    let ticket = tickets.loadThenWrappingIncrement(ordering: .relaxed)
    let cancellation = CancellationFlag()

    try await withTaskCancellationHandler {
      try await sleepers.park(
        ticket: ticket,
        until: deadline,
        cancellation: cancellation,
      )
    } onCancel: { [sleepers] in
      cancellation.raise()

      // Resumes the sleeper now, rather than at the next advance.
      Task {
        await sleepers.cancel(ticket: ticket)
      }
    }
  }

  /// Returns once a task is parked on this clock that no earlier call has returned for, and gives
  /// its deadline. A sleeper that was resumed before anyone asked is not counted.
  @discardableResult
  public func nextSleep() async -> Instant {
    await sleepers.nextSleeper()
  }

  /// Moves the clock on by `duration` and resumes every sleeper it has reached, earliest deadline
  /// first. Returns the deadlines resumed, in the order they were resumed; a sleeper whose task
  /// was cancelled is ended with `CancellationError` and not listed. The clock never goes back:
  /// a duration of zero or less moves nothing and resumes nothing.
  @discardableResult
  public func advance(by duration: Duration) async -> [Instant] {
    await sleepers.advance(by: duration)
  }
}
