import Foundation
import Testing
@testable import UseCasesCore

struct VerifyFinisherChoosingTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func finish(
    _ runIdentifier: String? = nil,
    runner: any TransformerRunning = MockTransformerRunner(answers: []),
  ) async throws -> VerifiedRun {
    try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: runIdentifier),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )
  }

  private func attempt(_ runIdentifier: String? = nil) async -> Result<VerifiedRun, VerifyError> {
    do {
      return try await .success(finish(runIdentifier))
    } catch {
      return .failure(error as? VerifyError ?? .storage("\(error)"))
    }
  }

  private func runFolder(_ run: String) -> URL {
    fixture.freshness.workspace.directory.location(of: ".use-cases/runs/\(run)")
  }

  /// A run that `verify --run` opened and never finished.
  private func openRunOpenedByRun() throws -> OpenRun {
    let loaded = try fixture.resolved()
    let draft = StartDraft(
      openedBy: .run,
      selected: [],
      validationsDigest: StoreSamples.digest("0"),
      routes: [],
      files: [],
      sources: [],
    )

    return try fixture.store.writer.openVerifyRun(
      draft,
      in: loaded.workspace.root,
    )
  }

  @Test
  func `without a started run there is nothing to finish`() async {
    await #expect(throws: VerifyError.noStartedRun) {
      try await finish()
    }
  }

  @Test
  func `a finished run cannot be finished again`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])

    _ = try await finish(runner: runner)

    await #expect(throws: VerifyError.noStartedRun) {
      try await finish()
    }

    let run = try #require(started.runIdentifier)
    await #expect(throws: VerifyError.alreadySealed(run)) {
      try await finish(run)
    }
  }

  @Test
  func `several started runs must be named`() async throws {
    let first = try fixture.start()
    let second = try fixture.start()
    let ids = try [#require(first.runIdentifier), #require(second.runIdentifier)]

    await #expect(throws: VerifyError.severalStartedRuns(ids)) {
      try await finish()
    }
    #expect(VerifyError.severalStartedRuns(ids).message.contains("name one with --run-id"))
  }

  @Test
  func `a named run is finished and the others stay open`() async throws {
    let first = try fixture.start()
    let second = try fixture.start()
    try fixture.writeReport(of: second)
    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])

    let verified = try await finish(
      second.runIdentifier,
      runner: runner,
    )

    #expect(verified.runIdentifier == second.runIdentifier)
    #expect(try fixture.history().unfinishedRuns.map(\.identifier.text) == [first.runIdentifier])
  }

  @Test(arguments: ["nope", "0123", "00000000000000000000000000000000"])
  func `a run id that names no run is refused`(text: String) async {
    await #expect(throws: VerifyError.noSuchRun(text)) {
      try await finish(text)
    }
  }

  @Test
  func `a run another process is finishing is refused, never waited for`() async throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)

    let outcome = try await fixture.store.locks.holding(run: runFolder(run)) {
      await attempt()
    }

    #expect(throws: VerifyError.beingFinished(run)) {
      try outcome?.get()
    }
    #expect(try fixture.history().unfinishedRuns.count == 1)
  }

  @Test
  func `a run that verify --run opened is never taken by a finish that does not name it`()
    async throws
  {
    _ = try openRunOpenedByRun()

    await #expect(throws: VerifyError.noStartedRun) {
      try await finish()
    }
  }

  @Test
  func `a run that verify --run opened and stopped can only be aborted`() async throws {
    let run = try openRunOpenedByRun().identifier.text

    await #expect(throws: VerifyError.stoppedBeforeFinishing(run)) {
      try await finish(run)
    }

    let message = VerifyError.stoppedBeforeFinishing(run).message
    #expect(message.contains("stopped before finishing it"))
    #expect(message.contains("--abort"))
  }

  @Test
  func `a run that verify --run opened and is still running is being finished`() async throws {
    let run = try openRunOpenedByRun().identifier.text

    let outcome = try await fixture.store.locks.holding(run: runFolder(run)) {
      await attempt(run)
    }

    #expect(throws: VerifyError.beingFinished(run)) {
      try outcome?.get()
    }
  }

  @Test
  func `results already in the run's log are not repeated by a second finish`() async throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)
    let log = runFolder(run).appendingPathComponent("results.jsonl")

    try Data("{}\n".utf8).write(to: log)

    await #expect(throws: VerifyError.stagedResults(run: run)) {
      try await finish()
    }
  }
}
