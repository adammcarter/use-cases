import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// `verify --run` from the start point to the seal (chapter 13, chapter 14). Its commands are
/// scripted at the process supervisor, behind the real executor, on a clock the test moves.
struct VerifyRunnerTests {
  private let fixture: VerifyFixture
  private let clock = TestClock()

  init() throws {
    fixture = try VerifyFixture(
      bridge: VerifyFixture.bridge(running: "true"),
    )
  }

  /// A runner whose commands are answered by `steps`, in order.
  private func runner(
    transformer: any TransformerRunning = MockTransformerRunner(answers: []),
    answering steps: [ScriptedProcessSupervisor.Step],
  ) -> (VerifyRunner, ScriptedProcessSupervisor) {
    let supervisor = ScriptedProcessSupervisor(inOrder: steps)

    return (
      fixture.runner(
        transformer: transformer,
        supervisor: supervisor,
        clock: clock,
      ),
      supervisor,
    )
  }

  /// A runner whose one command writes its report and ends with `code`, having printed
  /// `console`.
  private func reporting(
    transformer: any TransformerRunning = MockTransformerRunner(answers: []),
    console: String = "",
    exitCode code: Int32 = 0,
  ) -> VerifyRunner {
    runner(
      transformer: transformer,
      answering: [
        VerifyFixture.writingReport(
          console: console,
          exitCode: code,
        ),
      ],
    ).0
  }

  @Test
  func `the command writes its report, and the run is sealed with the verdict it gave`()
    async throws
  {
    let verified = try await fixture.run(reporting(transformer: fixture.answering()))

    #expect(verified.verdictCounts.map(\.status) == ["pass"])
    #expect(!verified.hasRunErrors)
    #expect(!verified.isCancelled)

    let history = try fixture.history()

    #expect(history.runs.count == 1)
    #expect(history.unfinishedRuns.isEmpty)
    #expect(history.runs.first?.termination == .completed)
  }

  @Test
  func `the source says which command ran, how it ended and for how long`() async throws {
    let writes = VerifyFixture.writingReport()
    let (runner, _) = try runner(
      transformer: fixture.answering(),
      answering: [
        { [clock] request in
          await clock.advance(by: .milliseconds(1500))

          return await writes(request)
        },
      ],
    )
    let verified = try await fixture.run(runner)
    let source = try #require(verified.manifest?.sources.first)

    #expect(source.command == ["sh", "-c", "true", "sh", "{report}"])
    #expect(source.exitCode == 0)
    #expect(source.seconds == 1.5)
    #expect(source.report == "reports/unit-tests/unit.xml")
  }

  @Test
  func `what the command printed is sealed in the run beside its report`() async throws {
    let verified = try await fixture.run(
      reporting(
        transformer: fixture.answering(),
        console: "hello\n",
      ),
    )
    let run = try #require(verified.runIdentifier)

    #expect(try fixture.read(".use-cases/runs/\(run)/outputs/unit-tests/console.txt") == "hello\n")
    #expect(try fixture.read(".use-cases/runs/\(run)/completion.json").contains(
      "\"unit-tests/console.txt\"",
    ))
  }

  @Test
  func `the run is opened by --run, locked while its commands run, and no --finish can take it`()
    async throws
  {
    let store = fixture.store
    let workspace = fixture.workspace
    let executor = MockRunCommandExecutor { _, run in
      let folder = store.folder(
        of: run.identifier,
        in: workspace,
      )
      let acquired = try? await store.locks.holding(run: folder.url) { true }
      let found = try? store.find(
        run.identifier.text,
        in: workspace,
      )
      var isOpenedByRun = false

      if case let .open(open)? = found {
        isOpenedByRun = open.stamp.openedBy == .run
      }

      return .ran(
        RanCommand(
          command: [acquired == nil && isOpenedByRun ? "right" : "wrong"],
          failure: nil,
          exitCode: 0,
          seconds: 0,
        ),
      )
    }

    let verified = try await fixture.run(
      fixture.runner(
        transformer: fixture.answering(),
        executor: executor,
      ),
    )

    #expect(verified.manifest?.sources.first?.command == ["right"])
  }

  @Test
  func `a started run left by a crashed --run is never finished by --finish, only aborted`()
    async throws
  {
    let opened = try fixture.openedRun()

    // The process that opened it is gone, and its lock with it.
    opened.lock.release()

    await #expect(throws: VerifyError.stoppedBeforeFinishing(opened.run.identifier.text)) {
      try await fixture.finisher(runner: MockTransformerRunner(answers: [])).finish(
        VerifyFinishRequest(runIdentifier: opened.run.identifier.text),
        in: fixture.resolved(),
        reloading: FixtureReloading(fixture),
      )
    }

    let aborted = try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: nil),
      in: fixture.workspace,
    )

    #expect(aborted.runIdentifier == opened.run.identifier.text)
    #expect(try fixture.history().runs.first?.termination == .interrupted)
  }

  // MARK: - Run errors

  @Test
  func `a non-zero exit with no failing test is a build failure, and the run has no verdict`()
    async throws
  {
    let verified = try await fixture.run(
      reporting(
        transformer: fixture.answering(),
        exitCode: 2,
      ),
    )

    #expect(verified.results.isEmpty)
    #expect(
      verified.errors
        == ["unit-tests: command exited 2 without any failing test (build failure?)"],
    )
    #expect(verified.manifest?.sources.first?.exitCode == 2)
  }

  @Test
  func `a failing test in a command that exited non-zero is judged from the report`() async throws {
    let verified = try await fixture.run(
      reporting(
        transformer: fixture.answering("fail"),
        exitCode: 1,
      ),
    )

    #expect(verified.verdictCounts.map(\.status) == ["fail"])
    #expect(!verified.hasRunErrors)
  }

  @Test
  func `a command that writes no report is a run error`() async throws {
    let (runner, _) = runner(
      answering: [ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))],
    )
    let verified = try await fixture.run(runner)

    #expect(verified.results.isEmpty)
    #expect(verified.errors.count == 1)
    #expect(
      verified.errors.first?.hasPrefix(
        "unit-tests: no report: nothing was written to reports/unit-tests/unit.xml ({report})",
      ) == true,
    )
  }

  @Test
  func `a validation with no run command is a run error that says to run the tests yourself`()
    async throws
  {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(lines: ["report: unit.xml"]),
    )

    let (runner, supervisor) = runner(answering: [])
    let verified = try await fixture.run(runner)
    let source = try #require(verified.manifest?.sources.first)

    #expect(await supervisor.requests.isEmpty)
    #expect(verified.results.isEmpty)
    #expect(verified.errors == ["unit-tests: \(RanCommand.missingWords)"])
    #expect(source.command == nil)
    #expect(source.exitCode == nil)
    #expect(source.seconds == nil)
  }

  @Test
  func `a command that times out is a run error, and its console is kept`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      VerifyFixture.bridge(
        running: "true",
        lines: ["timeout_seconds: 1"],
      ),
    )

    let (runner, _) = runner(
      answering: [
        { request in
          ScriptedProcessSupervisor.ended(
            .timedOut(after: request.timeout),
            "slow\n",
          )
        },
      ],
    )
    let verified = try await fixture.run(runner)
    let run = try #require(verified.runIdentifier)

    #expect(verified.errors == ["unit-tests: command timed out after 1 seconds"])
    #expect(try fixture.read(".use-cases/runs/\(run)/outputs/unit-tests/console.txt") == "slow\n")
  }

  // MARK: - Selection

  @Test
  func `only runs the validations it names`() async throws {
    let verified = try await fixture.run(
      reporting(transformer: fixture.answering()),
      only: ["unit-tests"],
    )

    #expect(verified.manifest?.sources.map(\.identifier.text) == ["unit-tests"])
  }

  @Test
  func `an unknown validation refuses the request before any run is written`() async throws {
    await #expect(
      throws: VerifyError.unknownValidations(
        ["nope"],
        known: ["unit-tests"],
      ),
    ) {
      try await fixture.run(
        fixture.runner(),
        only: ["nope"],
      )
    }

    #expect(fixture.runs().isEmpty)
  }

  @Test
  func `with no validation set up nothing is run and no run is written`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nvalidations: []\n",
    )

    let verified = try await fixture.run(fixture.runner())

    #expect(verified.runIdentifier == nil)
    #expect(verified.notes == [VerifyFinisher.nothingToRead])
    #expect(fixture.runs().isEmpty)
  }

  @Test
  func `the commands run one after another in the order of the bridge settings`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      """
      schema_version: 1
      validations:
        - id: second
          report: s.txt
          run: [sh, -c, 'echo second', sh, "{report}"]
          transformer: junit
        - id: first
          report: f.txt
          run: [sh, -c, 'echo first', sh, "{report}"]
          transformer: junit

      """,
    )

    let ended = ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))
    let (runner, supervisor) = runner(answering: [ended, ended])
    _ = try await fixture.run(runner)

    #expect(
      await supervisor.requests.map { $0.arguments[2] } == ["echo second", "echo first"],
    )
  }
}
