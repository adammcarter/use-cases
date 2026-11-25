import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// How a command's work is raced against its cancellation (chapter 13 §15), with the real
/// observed scope, a switch the test raises, a clock only the test moves, and work that waits at
/// a gate.
///
/// What these prove, and what they do not: the answer comes while the work is suspended. None of
/// them holds a thread while it waits, so none shows an answer given while the work keeps the
/// only thread of the pool busy; on a pool of one thread, a first cancellation of work that never
/// suspends is not answered until the work ends.
struct CommandLineRunnerRacedTests {
  private let folder: TemporaryFolder
  private let cancel: CancellationSwitch
  private let clock = TestClock()
  private let gate = UseCasesTestSupport.Gate()
  private let scope: WatchedCancellationScope

  init() throws {
    let cancel = CancellationSwitch()

    folder = try TemporaryFolder()
    self.cancel = cancel
    scope = WatchedCancellationScope {
      cancel
    }
  }

  private func runner() -> CommandLineRunner {
    CommandLineRunner(
      loader: WorkspaceLoader(),
      cancellation: scope,
      workingDirectory: folder.url,
      clock: clock,
    )
  }

  @Test
  func `a cancellation is answered at once while the work is suspended`() async throws {
    let (cancel, clock, gate) = (cancel, clock, gate)
    await scope.begin()

    // The work is at its gate and the watcher has looked once and is asleep; only then does the
    // cancellation come, and the clock moves to the watcher's next look.
    let driver = Task {
      await gate.nextWaiter()
      let deadline = await clock.nextSleep()
      cancel.raise()
      await clock.advance(by: clock.now.duration(to: deadline))
    }

    let result = await runner().raced(
      command: "validate",
      json: true,
    ) {
      await gate.wait()

      return .done("the work's own answer")
    }
    // The answer is in hand: a wrong one fails here, before waiting on the driver.
    try #require(await cancel.isCancelled())
    try #require(
      result == .cancelled(
        command: "validate",
        json: true,
      ),
    )
    await driver.value
    await gate.open()
  }

  @Test
  func `a write that has been claimed is not abandoned, and its own answer is the one returned`()
    async
  {
    let (cancel, clock, gate, scope) = (cancel, clock, gate, scope)
    await scope.begin()

    // Not awaited: under a runner that abandoned the write, its last wait never comes, and the
    // test must fail rather than hang.
    _ = Task {
      await gate.nextWaiter()
      let deadline = await clock.nextSleep()
      await clock.advance(by: clock.now.duration(to: deadline))
      // The watcher has looked with the cancellation raised and the write going on, and gone
      // back to sleep without answering.
      await clock.nextSleep()
      await gate.open()
    }

    let result = await runner().raced(
      command: "record",
      json: true,
    ) {
      guard await scope.claimWrite() else {
        return .done("the claim was refused")
      }

      cancel.raise()
      await gate.wait()

      return .done("written")
    }

    #expect(result == .done("written"))
    #expect(await scope.writingAsks > 0)
  }

  @Test
  func `a request already cancelled starts nothing`() async {
    let started = CancellationSwitch()
    cancel.raise()
    await scope.begin()

    let result = await runner().raced(
      command: "status",
      json: false,
    ) {
      started.raise()

      return .done("started")
    }

    // Work that had been started could answer first; a watcher that had been started asks
    // whether a write is going on before it answers. Neither may have happened.
    #expect(
      result == .cancelled(
        command: "status",
        json: false,
      ),
    )
    #expect(await scope.writingAsks == 0)
    #expect(await !started.isCancelled())
  }
}
