import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// No outcome here turns on how long anything takes. Where the command is a double, the clock is
/// moved by the test once the watcher waits on it. Where a real group is stopped, the command is
/// held until the test lets it go, and the clock is jumped past the time limit, or past the grace
/// a stop gives, only once the test has heard that the command is held, or took the TERM, and
/// that the watcher, or the stopper, has set its limit.
struct ProcessSupervisorTimeoutTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  // MARK: - What the supervisor makes of a time limit

  @Test
  func `a command still running when its time is up has timed out`() async throws {
    let clock = TestClock()
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      clock: clock,
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper.running,
      stopper: stopper,
    )
    let request = fixture.request(
      "true",
      timeout: .milliseconds(100),
    )

    let running = Task {
      try await supervisor.run(request)
    }

    @Sendable
    func parks() async {
      await clock.nextSleep()
    }

    @Sendable
    func ends() async {
      _ = await running.result
    }

    // The watcher waits on the clock before the test moves it, and is not over before then; once
    // it is moved, the run ends rather than waiting on the clock again.
    try #require(await EventRace.isFirst(parks, before: ends))
    await clock.advance(by: .milliseconds(100))
    try #require(await EventRace.isFirst(ends, before: parks))

    let run = try await running.value
    #expect(run.termination == .timedOut(after: .milliseconds(100)))
    #expect(await stopper.stopped == [777])
  }

  @Test
  func `a command that ends in time has not timed out`() async throws {
    let clock = TestClock()
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      clock: clock,
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper(answers: [.success(nil), .success(.exited(5))]),
      stopper: stopper,
    )
    let request = fixture.request(
      "true",
      timeout: .seconds(30),
    )

    let running = Task {
      try await supervisor.run(request)
    }

    @Sendable
    func parks() async {
      await clock.nextSleep()
    }

    @Sendable
    func ends() async {
      _ = await running.result
    }

    // The watcher waits on the clock before the test moves it, and is not over before then; once
    // it is moved, the run ends rather than waiting on the clock again.
    try #require(await EventRace.isFirst(parks, before: ends))
    await clock.advance(by: .seconds(29))
    try #require(await EventRace.isFirst(ends, before: parks))

    let run = try await running.value
    #expect(run.termination == .exited(5))
    #expect(await stopper.stopped.isEmpty)
  }

  @Test
  func `the console of a command that timed out is kept`() async throws {
    let clock = TestClock()
    let supervisor = fixture.supervisor(
      clock: clock,
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper.running,
      stopper: MockProcessGroupStopper(),
      console: ProcessConsole(
        text: "started\n",
        omittedByteCount: 0,
      ),
    )
    let request = fixture.request(
      "true",
      timeout: .seconds(30),
    )

    let running = Task {
      try await supervisor.run(request)
    }

    @Sendable
    func parks() async {
      await clock.nextSleep()
    }

    @Sendable
    func ends() async {
      _ = await running.result
    }

    // The watcher waits on the clock before the test moves it, and is not over before then; once
    // it is moved, the run ends rather than waiting on the clock again.
    try #require(await EventRace.isFirst(parks, before: ends))
    await clock.advance(by: .seconds(30))
    try #require(await EventRace.isFirst(ends, before: parks))

    let run = try await running.value
    #expect(run.termination == .timedOut(after: .seconds(30)))
    #expect(run.console.text == "started\n")
  }

  // MARK: - How a real group is stopped

  @Test
  func `a timeout stops the whole process group, grandchildren too`() async throws {
    let clock = OffsetClock()
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let holders = PipeHolders()
    let watcherReaper = ObservedProcessReaper()
    let supervisor = fixture.supervisor(
      clock: clock,
      holders: holders,
      watcherReaper: watcherReaper,
    )
    let grandchildScript = try fixture.script("grandchild.sh", hold.shellText())
    let request = fixture.request(
      "\(grandchildScript) & wait",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    let grandchild = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    await watcherReaper.asked.wait()
    clock.jump(by: ProcessFixture.timeLimitNoTestReaches)

    let run = try await running.value
    #expect(run.termination == .timedOut(after: ProcessFixture.timeLimitNoTestReaches))
    #expect(!ProcessFixture.exists(grandchild))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `a command that ignores SIGTERM is sent it first and killed after the grace`() async throws {
    let clock = OffsetClock()
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let said = try fixture.signal("said.fifo")
    let holders = PipeHolders()
    let watcherReaper = ObservedProcessReaper()
    let stopperReaper = ObservedProcessReaper()
    let supervisor = fixture.supervisor(
      clock: clock,
      holders: holders,
      watcherReaper: watcherReaper,
      stopperReaper: stopperReaper,
    )
    // The shell takes the TERM, says so, and goes back to its hold; only the kill that follows
    // the grace ends it.
    let request = fixture.request(
      "trap \"\(said.shellText(saying: "got-term"))\" TERM; \(hold.shellText())",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    // Once the run is over nothing more can be said, so a wait for the TERM ends with it.
    let running = Task {
      defer {
        said.close()
      }

      return try await supervisor.run(request)
    }

    let leader = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    await watcherReaper.asked.wait()
    clock.jump(by: ProcessFixture.timeLimitNoTestReaches)

    try #require(await said.next() == "got-term")
    await stopperReaper.asked.wait()
    clock.jump(by: ProcessFixture.terminationGrace)

    let run = try await running.value
    #expect(run.termination == .timedOut(after: ProcessFixture.timeLimitNoTestReaches))
    #expect(!ProcessFixture.exists(leader))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `a group member that ignores SIGTERM is killed when the leader ended on it`() async throws {
    let clock = OffsetClock()
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let holders = PipeHolders()
    let watcherReaper = ObservedProcessReaper()
    let stopperReaper = ObservedProcessReaper()
    let supervisor = fixture.supervisor(
      clock: clock,
      holders: holders,
      watcherReaper: watcherReaper,
      stopperReaper: stopperReaper,
    )
    // The member has the TERM ignored before it says it is held, so before any stop.
    let memberScript = try fixture.script("member.sh", "trap '' TERM; \(hold.shellText())")
    let request = fixture.request(
      "\(memberScript) & wait",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    let member = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    await watcherReaper.asked.wait()
    clock.jump(by: ProcessFixture.timeLimitNoTestReaches)

    // The grace runs out once the leader has ended on the TERM and been collected.
    try #require(await Self.wait(for: stopperReaper.collected, unlessEnded: running))
    clock.jump(by: ProcessFixture.terminationGrace)

    let run = try await running.value
    #expect(run.termination == .timedOut(after: ProcessFixture.timeLimitNoTestReaches))
    #expect(!ProcessFixture.exists(member))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `SIGTERM goes to the whole group, so a background child can clean up`() async throws {
    let clock = OffsetClock()
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let holders = PipeHolders()
    let watcherReaper = ObservedProcessReaper()
    let stopperReaper = ObservedProcessReaper()
    let supervisor = fixture.supervisor(
      clock: clock,
      holders: holders,
      watcherReaper: watcherReaper,
      stopperReaper: stopperReaper,
    )
    // bash on every system: what this pins is the stop, not how a shell runs a trap in a
    // background subshell, which dash and bash do differently. The subshell says it is held only
    // once its trap is set, so the TERM cannot come before the trap. What the trap did is looked
    // at only once the run is over, when the group, and so the trap, is done. The subshell is let
    // go once the leader was collected, after the TERM went out: one that was sent it runs its
    // trap before its next command, and one that was not ends without it.
    let script = "( trap 'touch got-term; exit' TERM; \(hold.shellText()) ) & wait"
    let request = ProcessRequest(
      arguments: ["/bin/bash", "-c", script],
      workingDirectory: fixture.directory.url,
      reportPath: nil,
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    _ = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    await watcherReaper.asked.wait()
    clock.jump(by: ProcessFixture.timeLimitNoTestReaches)

    // The subshell may end by its own trap as soon as the TERM reaches it, so the run may be over
    // by the time the leader is collected: either way, it is let go now.
    _ = await Self.wait(for: stopperReaper.collected, unlessEnded: running)
    hold.release()

    let run = try await running.value
    #expect(run.termination == .timedOut(after: ProcessFixture.timeLimitNoTestReaches))
    #expect(FileManager.default.fileExists(atPath: fixture.directory.location(of: "got-term").path))

    hold.release()
    await holders.allGone()
  }

  /// Waits for `gate`, unless the run ends first, and says whether the gate opened first. A run
  /// that ends without the gate opening is a failure the test reports, never a wait for ever, so
  /// the gate is then opened to let the wait go.
  private static func wait(
    for gate: UseCasesTestSupport.Gate,
    unlessEnded running: Task<ProcessRun, any Error>,
  ) async -> Bool {
    let (events, sink) = AsyncStream.makeStream(of: Bool.self)
    let opened = Task {
      await gate.wait()
      sink.yield(true)
    }
    Task {
      _ = try? await running.value
      sink.yield(false)
    }

    var iterator = events.makeAsyncIterator()
    let isOpenedFirst = await iterator.next() ?? false

    await gate.open()
    await opened.value

    return isOpenedFirst
  }
}
