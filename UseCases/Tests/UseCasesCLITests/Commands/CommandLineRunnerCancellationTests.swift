import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// What a cancellation does to each kind of command (chapter 13 §15, chapter 16 §6).
///
/// The cancellation is a switch the test raises, or a spy raises from inside a step. The runner's
/// watcher sleeps on a clock only the test moves, and work the test must catch in the middle is
/// held at a gate on an asynchronous seam, so no test holds a thread while it waits. What that
/// cannot show is in `CommandLineRunnerRacedTests`.
struct CommandLineRunnerCancellationTests {
  private static let recordSchema = "schemas/output/cli-record.schema.json"
  private static let verifySchema = "schemas/output/cli-verify.schema.json"
  private static let record = ["--json", "record", "shop.pay.card", "unit-tests", "pass"]

  private let workspace: VerifyWorkspace
  private let cancel = CancellationSwitch()
  private let clock = TestClock()

  init() throws {
    workspace = try VerifyWorkspace()
  }

  // MARK: - A write that has not begun

  /// The work has noted the code and waits to claim its write until the answer has been given;
  /// the claim it then makes is refused.
  @Test
  func `a start cancelled while the code is noted writes no run, and says cancelled`()
    async throws
  {
    let (result, scope) = try await cancelledAtClaim(["--json", "verify", "--start"])

    #expect(await scope.nextClaim() == false)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `a record cancelled while the route is fingerprinted writes no run, and says cancelled`()
    async throws
  {
    let (result, scope) = try await cancelledAtClaim(Self.record)

    #expect(await scope.nextClaim() == false)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `a start whose claim is refused answers cancelled itself, and writes no run`()
    async throws
  {
    let claims = UseCasesTestSupport.Gate()
    let scope = WatchedCancellationScope(
      observing: cancellation,
      holdingClaimsAt: claims,
    )
    let (cancel, clock) = (cancel, clock)

    // Not awaited: a work that never claims answers without it, and the test fails on that.
    _ = Task {
      await claims.nextWaiter()
      await clock.nextSleep()
      cancel.raise()
      await claims.open()
    }

    let result = await workspace.run(
      ["--json", "verify", "--start"],
      scope: scope,
      cancellation: cancellation,
      clock: clock,
    )

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `an abort cancelled before it began closes nothing`() async throws {
    _ = try await workspace.start()

    let result = await workspace.run(
      ["--json", "verify", "--abort"],
      cancellation: { MockCancellation.always },
      clock: clock,
    )

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(try await workspace.run(["--json", "verify", "--abort"])
      .document()["aborted"] == .boolean(true))
  }

  // MARK: - A write that has begun

  @Test
  func `a start cancelled once its run is written prints the run, with a note, and exits 0`()
    async throws
  {
    let result = await workspace.run(
      ["--json", "verify", "--start"],
      scope: ObservedCancellationScope(makeObserver: cancellation),
      cancellation: cancellation,
      starter: SpyVerifyStarter(
        afterPreparing: {},
        afterCommitting: cancel.raise,
      ),
      clock: clock,
    )
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try PublishedSchema(path: Self.verifySchema).failures(of: document) == [])
    #expect(document["started"] == .boolean(true))
    #expect(workspace.runs().count == 1)
    guard case let .array(notes)? = document["notes"] else {
      Issue.record("no notes")
      return
    }

    #expect(notes.last == .string("cancelled too late to stop the write: the run was started"))
  }

  @Test
  func `the same start in words says it under the run`() async {
    let result = await workspace.run(
      ["verify", "--start", "--quiet"],
      scope: ObservedCancellationScope(makeObserver: cancellation),
      cancellation: cancellation,
      starter: SpyVerifyStarter(
        afterPreparing: {},
        afterCommitting: cancel.raise,
      ),
      clock: clock,
    )

    #expect(result.exitCode == 0)
    #expect(
      result.standardOutput.split(separator: "\n").last
        == "cancelled too late to stop the write: the run was started",
    )
  }

  @Test
  func `a record cancelled once its run is written prints the verdict, with a note, and exits 0`()
    async throws
  {
    let result = await workspace.run(
      Self.record,
      scope: ObservedCancellationScope(makeObserver: cancellation),
      cancellation: cancellation,
      recorder: SpyVerdictRecorder(
        afterPlanning: {},
        whileCommitting: {},
        afterCommitting: cancel.raise,
      ),
      clock: clock,
    )
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try PublishedSchema(path: Self.recordSchema).failures(of: document) == [])
    #expect(
      document["notes"] ==
        .array([.string("cancelled too late to stop the write: the verdict was recorded")]),
    )
    #expect(workspace.runs().count == 1)
  }

  @Test
  func `an abort cancelled once the run is closed prints it, with a note, and exits 0`()
    async throws
  {
    _ = try await workspace.start()

    let result = await workspace.run(
      ["--json", "verify", "--abort"],
      scope: ObservedCancellationScope(makeObserver: cancellation),
      cancellation: cancellation,
      aborter: SpyVerifyAborter(afterAborting: cancel.raise),
      clock: clock,
    )
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try PublishedSchema(path: Self.verifySchema).failures(of: document) == [])
    #expect(document["aborted"] == .boolean(true))
    #expect(
      document["notes"] ==
        .array([.string("cancelled too late to stop the write: the run was closed")]),
    )
  }

  /// The claim to write is granted and the write waits; then the cancellation comes, and the
  /// watcher looks, finds the write going on, and goes back to sleep. Only then does the write go
  /// on: its answer is the one given.
  @Test
  func `a write that has begun is not abandoned for a cancellation that comes while it runs`()
    async throws
  {
    let writes = UseCasesTestSupport.Gate()
    let scope = WatchedCancellationScope(
      observing: cancellation,
      holdingWritesAt: writes,
    )
    let (cancel, clock) = (cancel, clock)

    // Not awaited: under a runner that abandoned the write, its last wait never comes, and the
    // test must fail rather than hang.
    _ = Task {
      await writes.nextWaiter()
      cancel.raise()
      let deadline = await clock.nextSleep()
      await clock.advance(by: clock.now.duration(to: deadline))
      await clock.nextSleep()
      await writes.open()
    }

    let result = await workspace.run(
      Self.record,
      scope: scope,
      cancellation: cancellation,
      clock: clock,
    )

    #expect(await scope.writingAsks > 0)
    #expect(result.exitCode == 0)
    #expect(try result.document()["error"] == nil)
    #expect(workspace.runs().count == 1)
  }

  // MARK: - Promptness

  /// The work waits for its links until the answer has been given: a command that waited for
  /// its work would never answer, so the test would not end. The work is suspended, holding no
  /// thread; work that keeps a thread busy is not shown here (see `CommandLineRunnerRacedTests`).
  @Test(arguments: ["validate", "links", "status"])
  func `a command that reads is answered at once while its work is still going`(
    command: String,
  ) async throws {
    let links = UseCasesTestSupport.Gate()
    let canceller = cancelWhileWaiting(at: links)

    let result = await workspace.run(
      ["--json", command],
      scope: ObservedCancellationScope(makeObserver: cancellation),
      cancellation: cancellation,
      transformers: GatedTransformerLinks(
        gate: links,
        links: TransformerLinkResolver(cancellation: cancellation),
      ),
      deliver: { _ in
        await links.open()
      },
      clock: clock,
    )
    // The answer is in hand: a wrong one fails here, before waiting on what only a right one
    // brings about.
    try #require(await cancel.isCancelled())
    try #require(result.exitCode == 130)
    await canceller.value

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
  }

  // MARK: - The answer is written with the signals held

  @Test
  func `the signals are held until the answer has been delivered, and given back after`()
    async
  {
    let probe = ScopeProbe()

    _ = await workspace.run(
      ["--json", "validate"],
      scope: probe,
      deliver: { _ in
        await probe.record("delivered")
      },
      clock: clock,
    )

    #expect(await probe.events == ["begin", "delivered", "end"])
  }

  @Test
  func `a command line that cannot be read is delivered too`() async {
    let probe = ScopeProbe()

    _ = await workspace.run(
      ["--json", "bogus"],
      scope: probe,
      deliver: { _ in
        await probe.record("delivered")
      },
      clock: clock,
    )

    #expect(await probe.events == ["delivered"])
  }

  // MARK: - record --interactive

  @Test
  func `an interactive record takes the signals over only for its write, not while it asks`()
    async
  {
    let probe = ScopeProbe()
    let prompter = ProbingPrompter(
      prompter: MockPrompter(answers: ["shop.pay.card", "unit-tests", "pass", ""]),
      probe: probe,
    )

    let result = await workspace.run(
      ["record", "--interactive"],
      scope: probe,
      prompter: prompter,
      isTerminal: true,
      deliver: { _ in
        await probe.record("delivered")
      },
      clock: clock,
    )
    let events = await probe.events

    #expect(result.exitCode == 0)
    #expect(events.first == "asked")
    #expect(events.drop { $0 == "asked" } == ["begin", "claim", "end", "delivered"])
  }

  @Test
  func `an interactive record cancelled at its write stores nothing`() async {
    let prompter = MockPrompter(answers: ["shop.pay.card", "unit-tests", "pass", ""])

    let result = await workspace.run(
      ["record", "--interactive"],
      cancellation: { MockCancellation.always },
      prompter: prompter,
      isTerminal: true,
      clock: clock,
    )

    #expect(result.exitCode == 130)
    #expect(workspace.runs().isEmpty)
  }
}

extension CommandLineRunnerCancellationTests {
  /// What the command and everything it runs observe: the test's switch.
  private var cancellation: @Sendable () -> any CancellationObserving {
    let cancel = cancel

    return {
      cancel
    }
  }

  /// The test's side of a cancellation that comes while the work waits at `gate`: once the work
  /// is there and the watcher has looked once and gone to sleep, the switch is raised and the
  /// clock moved to the watcher's next look.
  private func cancelWhileWaiting(at gate: UseCasesTestSupport.Gate) -> Task<Void, Never> {
    let (cancel, clock) = (cancel, clock)

    return Task {
      await gate.nextWaiter()
      let deadline = await clock.nextSleep()
      cancel.raise()
      await clock.advance(by: clock.now.duration(to: deadline))
    }
  }

  /// Runs `arguments` with the work held where it claims its write. Once the watcher has looked
  /// and gone to sleep the switch is raised and the clock moved to its next look; the claim goes
  /// on once the answer has been delivered. The answer must be the cancellation before the test
  /// waits on anything only a right answer brings about.
  private func cancelledAtClaim(
    _ arguments: [String],
  ) async throws -> (CommandResult, WatchedCancellationScope) {
    let claims = UseCasesTestSupport.Gate()
    let scope = WatchedCancellationScope(
      observing: cancellation,
      holdingClaimsAt: claims,
    )
    let canceller = cancelWhileWaiting(at: claims)

    let result = await workspace.run(
      arguments,
      scope: scope,
      cancellation: cancellation,
      deliver: { _ in
        await claims.open()
      },
      clock: clock,
    )
    try #require(await cancel.isCancelled())
    try #require(result.exitCode == 130)
    await canceller.value

    return (result, scope)
  }
}
