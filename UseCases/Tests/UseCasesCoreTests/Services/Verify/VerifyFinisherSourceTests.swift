import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct VerifyFinisherSourceTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func finish(
    runner: any TransformerRunning = MockTransformerRunner(answers: []),
    cancellation: any CancellationObserving = MockCancellation.never,
  ) async throws -> VerifiedRun {
    try await fixture.finisher(
      runner: runner,
      cancellation: cancellation,
    ).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )
  }

  // MARK: - Run errors

  @Test
  func `no report is a run error, and the transformer is never asked`() async throws {
    _ = try fixture.start()
    let runner = MockTransformerRunner(answers: [])

    let verified = try await finish(runner: runner)

    #expect(verified.results.isEmpty)
    #expect(verified.hasRunErrors)
    #expect(
      verified.errors == [
        "unit-tests: no report: nothing was written to reports/unit-tests/unit.xml "
          + "(the path `--start` gave)",
      ],
    )
    #expect(await runner.calls.isEmpty)
    #expect(try fixture.history().runs.count == 1)
  }

  @Test
  func `an empty reports folder is no report when the validation names none`() async throws {
    let bare = try VerifyFixture(bridge: BridgeFileSamples.validation())
    let started = try bare.start()
    let path = try #require(started.reports.first).path

    #expect(path.hasSuffix("/reports/unit-tests"))

    let verified = try await bare.finisher(runner: MockTransformerRunner(answers: [])).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: bare.resolved(),
      reloading: FixtureReloading(bare),
    )

    #expect(verified.errors.first?
      .contains("no report: nothing was written to reports/unit-tests") == true)
  }

  @Test
  func `any entry in the reports folder counts as a report`() async throws {
    let bare = try VerifyFixture(bridge: BridgeFileSamples.validation())
    let started = try bare.start()
    let path = try #require(started.reports.first).path

    try Data().write(to: URL(fileURLWithPath: path + "/.DS_Store"))

    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])
    let verified = try await bare.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: bare.resolved(),
      reloading: FixtureReloading(bare),
    )

    #expect(verified.errors.isEmpty)
    #expect(await runner.calls.count == 1)
  }

  @Test
  func `a broken transformer is a run error, never a verdict`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = MockTransformerRunner(
      answers: [.failure(.exited(name: "junit", code: 3, console: ""))],
    )

    let verified = try await finish(runner: runner)

    #expect(verified.results.isEmpty)
    #expect(verified.errors == ["unit-tests: transformer error, no results used: junit exited 3"])
  }

  @Test
  func `a result for a link that is not in the request is a run error`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response(["made-up": "fail"]))],
    )

    let verified = try await finish(runner: runner)

    #expect(verified.results.isEmpty)
    #expect(verified.errors.first?.contains("does not exist") == true)
  }

  @Test
  func `a report that changes while it is read gives no results, and is sealed as it was read`()
    async throws
  {
    let started = try fixture.start()
    let report = try #require(started.reports.first).path
    try fixture.writeReport(of: started, "first")
    let runner = ClosureTransformerRunner { _ in
      try? Data("first and a late line".utf8).write(to: URL(fileURLWithPath: report))

      return (try? .json(#"{"contract":1,"results":[],"unlinked":[],"diagnostics":[]}"#))
        ?? .object([])
    }

    let verified = try await finish(runner: runner)
    let run = try #require(verified.runIdentifier)
    let sealed = try fixture.read(".use-cases/runs/\(run)/completion.json")

    #expect(verified.results.isEmpty)
    #expect(verified.errors == ["unit-tests: report changed while it was read"])
    #expect(sealed.contains(SHA256Hasher().sha256Hex(of: Array("first".utf8))))
    #expect(try fixture.history().findings.map(\.description).count == 1)
  }

  // MARK: - The settings the run was started with

  @Test(arguments: [
    ("report: unit.xml", "report: other.xml"),
    ("transformer: junit", "transformer: exit-code"),
  ])
  func `settings changed since the start refuse the finish and leave the run open`(
    old: String,
    new: String,
  ) async throws {
    let started = try fixture.start()
    let bridge = try fixture.read("use-cases-bridge.yml")

    try fixture.freshness.write(
      "use-cases-bridge.yml",
      bridge.replacingOccurrences(of: old, with: new),
    )

    let run = try #require(started.runIdentifier)
    await #expect(throws: VerifyError.settingsChanged(run: run)) {
      try await finish()
    }
    #expect(try fixture.history().unfinishedRuns.count == 1)
    #expect(
      VerifyError.settingsChanged(run: run).message
        .contains("changed for this run's validations since `--start`"),
    )
  }

  @Test
  func `a bridge file that was deleted is a change, never nothing set up`() async throws {
    let started = try fixture.start()

    try FileManager.default.removeItem(
      at: fixture.freshness.workspace.directory.location(of: "use-cases-bridge.yml"),
    )

    let run = try #require(started.runIdentifier)
    await #expect(throws: VerifyError.settingsChanged(run: run)) {
      try await finish()
    }
  }

  @Test
  func `settings of validations the run did not select can change`() async throws {
    let two = try VerifyFixture(
      bridge: BridgeFileSamples.validation(lines: ["report: unit.xml"])
        + "  - id: style\n    transformer: exit-code\n",
    )
    let started = try two.start(only: ["unit-tests"])

    try two.freshness.write(
      "use-cases-bridge.yml",
      two.read("use-cases-bridge.yml").replacingOccurrences(of: "exit-code", with: "junit"),
    )
    try two.writeReport(of: started)

    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])
    let verified = try await two.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: two.resolved(),
      reloading: FixtureReloading(two),
    )

    #expect(verified.manifest?.sources.map(\.identifier.text) == ["unit-tests"])
  }

  // MARK: - Cancellation

  @Test
  func `a cancelled finish is sealed as interrupted with no verdicts`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = MockTransformerRunner(answers: [.failure(.cancelled)])

    let verified = try await finish(runner: runner)
    let run = try #require(try fixture.history().runs.first)

    #expect(verified.isCancelled)
    #expect(verified.results.isEmpty)
    #expect(verified.notes == ["cancelled before judging; sources not processed: unit-tests"])
    #expect(run.termination == .interrupted)
    #expect(run.results.isEmpty)
  }

  @Test
  func `a signal that came after the last report was read is still a cancellation`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])

    let verified = try await finish(
      runner: runner,
      cancellation: MockCancellation.always,
    )

    #expect(verified.isCancelled)
    #expect(verified.notes == ["cancelled before judging"])
    #expect(try fixture.history().runs.first?.termination == .interrupted)
  }
}
