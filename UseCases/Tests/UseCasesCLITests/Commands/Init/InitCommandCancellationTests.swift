import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct InitCommandCancellationTests {
  private static let everything = [
    "use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml",
  ]

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  // MARK: - Cancellation

  /// The watcher looks once and sleeps, the work is held where it would claim its write, and
  /// only then does the cancellation come, the clock move to the watcher's next look, and the
  /// claim go on.
  @Test
  func `a request cancelled before the write begins writes nothing`() async throws {
    let cancel = CancellationSwitch()
    let clock = TestClock()
    let claims = UseCasesTestSupport.Gate()
    let log = place.scratch.url.appendingPathComponent("log")
    let scope = WatchedCancellationScope(
      observing: {
        cancel
      },
      holdingClaimsAt: claims,
    )
    await scope.begin()

    let canceller = Task {
      await claims.nextWaiter()
      let deadline = await clock.nextSleep()
      cancel.raise()
      await clock.advance(by: clock.now.duration(to: deadline))
      await claims.open()
    }

    let result = await place.run(
      ["--json", "init", "--no-input"],
      writer: SpyPlanWriting(log: log),
      cancellation: scope,
      clock: clock,
    )
    // The answer is in hand: a wrong one fails here, before waiting on what only a right one
    // brings about.
    try #require(await cancel.isCancelled())
    try #require(result.exitCode == 130)
    await canceller.value

    #expect(await scope.nextClaim() == false)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(try place.snapshot().isEmpty)
    #expect(SpyPlanWriting(log: log).applied.isEmpty)
  }

  @Test
  func `a request cancelled once the write began finishes it and says so`() async throws {
    let cancel = CancellationSwitch()
    let log = place.scratch.url.appendingPathComponent("log")
    let scope = ObservedCancellationScope(
      makeObserver: {
        cancel
      },
    )
    await scope.begin()

    let result = await place.run(
      ["--json", "init", "--no-input"],
      writer: SpyPlanWriting(
        log: log,
        afterApplying: cancel.raise,
      ),
      cancellation: scope,
      clock: TestClock(),
    )
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(document["created"]?.strings == Self.everything)
    #expect(document["notes"]?.strings.last?.hasPrefix("cancelled too late") == true)
    #expect(try place.snapshot().keys.sorted() == Self.everything.sorted())
  }

  @Test
  func `the plan is checked once and written once, to the workspace itself`() async {
    let log = place.scratch.url.appendingPathComponent("log")

    _ = await place.run(
      ["init", "--no-input"],
      writer: SpyPlanWriting(log: log),
      clock: TestClock(),
    )

    #expect(SpyPlanWriting(log: log).applied == [place.realPath])
  }
}
