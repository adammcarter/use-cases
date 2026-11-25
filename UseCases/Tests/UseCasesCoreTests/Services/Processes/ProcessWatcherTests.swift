import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// The clock moves only when the test moves it, and only once the watcher is waiting on it.
struct ProcessWatcherTests {
  private let clock = TestClock()

  private func watcher(
    reaper: MockProcessReaper,
    stopper: MockProcessGroupStopper,
  ) -> ProcessWatcher<TestClock> {
    ProcessWatcher(
      cancellation: MockCancellation.never,
      clock: clock,
      pollInterval: .milliseconds(1),
      reaper: reaper,
      stopper: stopper,
    )
  }

  @Test
  func `a command with no time limit is never timed out, however late the clock reads`(
  ) async throws {
    let stopper = MockProcessGroupStopper()
    let watcher = watcher(
      reaper: MockProcessReaper(
        answers: [.success(nil), .success(nil), .success(nil), .success(.exited(0))],
      ),
      stopper: stopper,
    )

    let watching = Task {
      try await watcher.watch(
        leader: 1,
        timeout: nil,
      )
    }

    // Three looks find it running, each a day after the last; the fourth finds it ended. The
    // clock is moved from beside the watch, so a watch that ends early is seen at once.
    let clock = clock
    let days = Task {
      for _ in 0 ..< 3 {
        await clock.nextSleep()
        await clock.advance(by: .seconds(86400))
      }
    }

    let termination = try await watching.value

    #expect(termination == .exited(0))
    #expect(await stopper.stopped.isEmpty)

    if termination == .exited(0) {
      await days.value
    }
  }

  @Test
  func `a command with a time limit is timed out when the clock reads past it`() async throws {
    let stopper = MockProcessGroupStopper()
    let watcher = watcher(
      reaper: MockProcessReaper.running,
      stopper: stopper,
    )

    let watching = Task {
      try await watcher.watch(
        leader: 7,
        timeout: .seconds(30),
      )
    }

    let clock = clock

    @Sendable
    func parks() async {
      await clock.nextSleep()
    }

    @Sendable
    func ends() async {
      _ = await watching.result
    }

    // Short of the limit, the command is looked at again and left running.
    try #require(await EventRace.isFirst(parks, before: ends))
    await clock.advance(by: .seconds(29))
    try #require(await EventRace.isFirst(parks, before: ends))
    #expect(await stopper.stopped.isEmpty)

    // Past it, the watch ends rather than looking again.
    await clock.advance(by: .seconds(2))
    try #require(await EventRace.isFirst(ends, before: parks))

    #expect(try await watching.value == .timedOut(after: .seconds(30)))
    #expect(await stopper.stopped == [7])
  }
}
