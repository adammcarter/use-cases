import Testing
import UseCasesTestSupport

// No outcome here turns on how long anything takes: a jump can only add to the time that has
// really passed, and a sleep that should end at once would otherwise last an hour.
struct OffsetClockTests {
  private let clock = OffsetClock()

  @Test
  func `the clock reads the real time moved on by every jump made so far`() {
    let before = clock.now

    clock.jump(by: .seconds(3600))
    clock.jump(by: .seconds(3600))

    #expect(before.duration(to: clock.now) >= .seconds(7200))
  }

  @Test
  func `a sleep until a deadline a jump has passed returns at once`() async throws {
    let deadline = clock.now.advanced(by: .seconds(3600))

    clock.jump(by: .seconds(3600))

    try await clock.sleep(until: deadline)
  }

  @Test
  func `a sleep of zero or less returns at once`() async throws {
    try await clock.sleep(for: .zero)
    try await clock.sleep(for: .seconds(-3600))
  }

  @Test
  func `a cancelled sleep throws CancellationError`() async {
    let sleep = Task {
      try await clock.sleep(for: .seconds(3600))
    }

    sleep.cancel()

    await #expect(throws: CancellationError.self) {
      try await sleep.value
    }
  }
}
