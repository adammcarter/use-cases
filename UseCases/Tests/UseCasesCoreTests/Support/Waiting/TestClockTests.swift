import Testing
@testable import UseCasesTestSupport

struct TestClockTests {
  private let clock = TestClock()

  private func at(_ duration: Duration) -> TestClock.Instant {
    TestClock.Instant(offset: duration)
  }

  @Test
  func `the clock reads its start until the test advances it, then reads every advance`() async {
    #expect(clock.now == at(.zero))

    await clock.advance(by: .seconds(3))
    await clock.advance(by: .milliseconds(500))

    #expect(clock.now == at(.milliseconds(3500)))
  }

  @Test
  func `a sleep of zero or less, or to a deadline already reached, returns without parking`(
  ) async throws {
    try await clock.sleep(for: .zero)
    try await clock.sleep(for: .seconds(-1))
    await clock.advance(by: .seconds(5))
    try await clock.sleep(until: at(.seconds(2)))
    try await clock.sleep(until: at(.seconds(5)))

    let later = Task {
      try await clock.sleep(for: .seconds(7))
    }

    // Had any of the sleeps above parked, it would be the one reported here.
    #expect(await clock.nextSleep() == at(.seconds(12)))
    await clock.advance(by: .seconds(7))
    try await later.value
  }

  @Test
  func `the next sleep is reported once a task has parked`(
  ) async throws {
    let listener = Task {
      await clock.nextSleep()
    }
    let sleep = Task {
      try await clock.sleep(for: .seconds(4))
    }

    #expect(await listener.value == at(.seconds(4)))
    await clock.advance(by: .seconds(4))
    try await sleep.value
  }

  @Test
  func `each ask reports a different parked sleeper`() async throws {
    let first = Task {
      try await clock.sleep(for: .seconds(1))
    }
    let second = Task {
      try await clock.sleep(for: .seconds(2))
    }

    let reported: Set = await [clock.nextSleep(), clock.nextSleep()]

    #expect(reported == [at(.seconds(1)), at(.seconds(2))])
    await clock.advance(by: .seconds(2))
    try await first.value
    try await second.value
  }

  @Test
  func `advancing resumes the sleepers it reaches earliest first and leaves the rest parked`(
  ) async throws {
    var sleeps: [Task<Void, any Error>] = []

    for seconds in [30, 10, 20, 40] {
      sleeps.append(
        Task {
          try await clock.sleep(for: .seconds(seconds))
        },
      )
      await clock.nextSleep()
    }

    let reached = [10, 20, 30].map { seconds in
      at(.seconds(seconds))
    }

    #expect(await clock.advance(by: .seconds(30)) == reached)

    for sleep in sleeps.prefix(3) {
      try await sleep.value
    }

    #expect(await clock.advance(by: .seconds(10)) == [at(.seconds(40))])
    try await sleeps[3].value
  }

  @Test
  func `several sleepers at one deadline all resume on the advance that reaches it`(
  ) async throws {
    var sleeps: [Task<Void, any Error>] = []

    for _ in 0 ..< 3 {
      sleeps.append(
        Task {
          try await clock.sleep(until: at(.seconds(5)))
        },
      )
      await clock.nextSleep()
    }

    #expect(await clock.advance(by: .seconds(5)) == Array(repeating: at(.seconds(5)), count: 3))

    for sleep in sleeps {
      try await sleep.value
    }
  }

  @Test
  func `a task that sleeps again and again is reported at each of its sleeps`() async throws {
    let looping = Task {
      for _ in 0 ..< 3 {
        try await clock.sleep(for: .seconds(1))
      }
    }

    for second in 1 ... 3 {
      #expect(await clock.nextSleep() == at(.seconds(second)))
      await clock.advance(by: .seconds(1))
    }

    try await looping.value
  }

  @Test
  func `advancing with nobody parked moves the clock and resumes nothing`() async {
    #expect(await clock.advance(by: .seconds(1)).isEmpty)
    #expect(clock.now == at(.seconds(1)))
  }

  @Test
  func `advancing by zero or less moves nothing`() async {
    await clock.advance(by: .seconds(2))

    #expect(await clock.advance(by: .zero).isEmpty)
    #expect(await clock.advance(by: .seconds(-1)).isEmpty)
    #expect(clock.now == at(.seconds(2)))
  }

  @Test
  func `a sleeper cancelled while parked throws CancellationError and is resumed no more`(
  ) async {
    let sleep = Task {
      try await clock.sleep(for: .seconds(1))
    }

    await clock.nextSleep()
    sleep.cancel()

    await #expect(throws: CancellationError.self) {
      try await sleep.value
    }
    #expect(await clock.advance(by: .seconds(1)).isEmpty)
  }

  @Test
  func `a sleeper cancelled while parked throws even when an advance reaches the clock first`(
  ) async {
    let sleep = Task {
      try await clock.sleep(for: .seconds(1))
    }

    await clock.nextSleep()
    sleep.cancel()

    #expect(await clock.advance(by: .seconds(1)).isEmpty)
    await #expect(throws: CancellationError.self) {
      try await sleep.value
    }
  }

  @Test
  func `a sleep whose cancel reached the clock before it parked throws at once`() async {
    let sleepers = TestClockSleepers()
    let cancellation = CancellationFlag()

    cancellation.raise()

    await #expect(throws: CancellationError.self) {
      try await sleepers.park(
        ticket: 0,
        until: at(.seconds(1)),
        cancellation: cancellation,
      )
    }
  }

  @Test
  func `a sleep far beyond what nanoseconds can count parks, and an advance as far resumes it`(
  ) async throws {
    let far = Duration.seconds(10_000_000_000)
    let sleep = Task {
      try await clock.sleep(for: far)
    }

    #expect(await clock.nextSleep() == at(far))
    #expect(await clock.advance(by: far) == [at(far)])
    try await sleep.value
  }

  @Test
  func `a duration too long to count in nanoseconds reads as the most there can be`() {
    #expect(Duration.seconds(Int64.max).wholeNanoseconds == Int64.max)
    #expect(Duration.seconds(Int64.min).wholeNanoseconds == Int64.min)
    #expect((Duration.seconds(9_223_372_036) + .milliseconds(900)).wholeNanoseconds == Int64.max)
    #expect(Duration.milliseconds(-1500).wholeNanoseconds == -1_500_000_000)
  }

  @Test
  func `a sleep in a task already cancelled throws without parking`() async throws {
    let sleep = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      try await clock.sleep(for: .seconds(1))
    }

    await #expect(throws: CancellationError.self) {
      try await sleep.value
    }

    let later = Task {
      try await clock.sleep(for: .seconds(2))
    }

    #expect(await clock.nextSleep() == at(.seconds(2)))
    await clock.advance(by: .seconds(2))
    try await later.value
  }
}
