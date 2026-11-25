import Atomics

/// The tasks parked on a `TestClock`, and the tests waiting to hear that one has parked.
actor TestClockSleepers {
  private struct Sleeper {
    let ticket: Int
    let deadline: TestClock.Instant
    let cancellation: CancellationFlag
    let continuation: CheckedContinuation<Void, any Error>
    var isNoticed: Bool
  }

  /// How far the clock has been advanced, in nanoseconds: read without waiting, because the
  /// clock's `now` is synchronous, and written only here.
  nonisolated let elapsed = ManagedAtomic<Int64>(0)

  private var sleepers: [Sleeper] = []
  private var listeners: [CheckedContinuation<TestClock.Instant, Never>] = []

  func park(
    ticket: Int,
    until deadline: TestClock.Instant,
    cancellation: CancellationFlag,
  ) async throws {
    // A cancel that reached this actor before the sleeper did found nothing to end.
    if cancellation.isRaised {
      throw CancellationError()
    }

    if deadline.offset.wholeNanoseconds <= elapsed.load(ordering: .acquiring) {
      return
    }

    try await withCheckedThrowingContinuation { continuation in
      sleepers.append(
        Sleeper(
          ticket: ticket,
          deadline: deadline,
          cancellation: cancellation,
          continuation: continuation,
          isNoticed: false,
        ),
      )
      tellListeners()
    }
  }

  func cancel(ticket: Int) {
    guard let index = sleepers.firstIndex(where: { $0.ticket == ticket }) else {
      return
    }

    sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  func nextSleeper() async -> TestClock.Instant {
    await withCheckedContinuation { continuation in
      listeners.append(continuation)
      tellListeners()
    }
  }

  func advance(by duration: Duration) -> [TestClock.Instant] {
    guard duration > .zero else {
      return []
    }

    let now = elapsed.load(ordering: .acquiring).addingSaturated(duration.wholeNanoseconds)
    elapsed.store(
      now,
      ordering: .releasing,
    )

    let due = sleepers
      .filter { $0.deadline.offset.wholeNanoseconds <= now }
      .sorted { earlier, later in
        (earlier.deadline, earlier.ticket) < (later.deadline, later.ticket)
      }
    sleepers.removeAll { $0.deadline.offset.wholeNanoseconds <= now }

    var resumed: [TestClock.Instant] = []

    for sleeper in due {
      if sleeper.cancellation.isRaised {
        sleeper.continuation.resume(throwing: CancellationError())
      } else {
        sleeper.continuation.resume()
        resumed.append(sleeper.deadline)
      }
    }

    return resumed
  }

  /// The one place a parked sleeper is matched with a test that asked, whichever came first.
  private func tellListeners() {
    while !listeners.isEmpty, let index = sleepers.firstIndex(where: { !$0.isNoticed }) {
      sleepers[index].isNoticed = true
      listeners.removeFirst().resume(returning: sleepers[index].deadline)
    }
  }
}
