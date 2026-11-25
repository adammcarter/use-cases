import Testing
import UseCasesTestSupport
@testable import UseCasesMCP

struct ShutdownWatcherTests {
  private static let interval = Duration.milliseconds(100)

  @Test
  func `a process already told to stop is seen at the first look`() async {
    let watcher = ShutdownWatcher(
      observer: MockCancellation.always,
      clock: TestClock(),
      pollInterval: Self.interval,
    )

    #expect(await watcher.waitsForShutdown())
  }

  @Test
  func `a process told to stop later is seen at the look after`() async {
    let observer = CountingCancellation(raisedAt: 3)
    let clock = TestClock()
    let watcher = ShutdownWatcher(
      observer: observer,
      clock: clock,
      pollInterval: Self.interval,
    )

    let waiting = Task {
      await watcher.waitsForShutdown()
    }
    // Each time to the deadline the watcher parked on, so a wrong interval is seen, not waited on.
    let firstSleep = await clock.nextSleep()
    await clock.advance(by: clock.now.duration(to: firstSleep))
    let secondSleep = await clock.nextSleep()
    await clock.advance(by: clock.now.duration(to: secondSleep))

    #expect(await waiting.value)
    #expect(await observer.looks == 3)
    #expect(firstSleep == TestClock.Instant(offset: Self.interval))
    #expect(secondSleep == TestClock.Instant(offset: Self.interval * 2))
  }

  @Test
  func `waiting cancelled while parked between looks says the process was never told`() async {
    let clock = TestClock()
    let watcher = ShutdownWatcher(
      observer: MockCancellation.never,
      clock: clock,
      pollInterval: Self.interval,
    )

    let waiting = Task {
      await watcher.waitsForShutdown()
    }
    await clock.nextSleep()
    waiting.cancel()

    #expect(await !waiting.value)
  }

  @Test
  func `waiting cancelled before any look says the process was never told, and asks nothing`(
  ) async {
    let observer = CountingCancellation(raisedAt: 1)
    let watcher = ShutdownWatcher(
      observer: observer,
      clock: TestClock(),
      pollInterval: Self.interval,
    )
    let start = Gate()

    let waiting = Task {
      await start.wait()

      return await watcher.waitsForShutdown()
    }
    // Cancelled while held at the gate, so the watcher begins already cancelled.
    await start.nextWaiter()
    waiting.cancel()
    await start.open()

    #expect(await !waiting.value)
    #expect(await observer.looks == 0)
  }
}
