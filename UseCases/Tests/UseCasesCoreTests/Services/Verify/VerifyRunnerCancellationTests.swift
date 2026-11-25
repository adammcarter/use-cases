import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// A cancelled `verify --run` (chapter 13 §15, chapter 14 §14).
///
/// The commands are scripted at the process supervisor, behind the real executor: a command that
/// is stopped raises the cancellation while it runs and ends as the supervisor then reports it.
struct VerifyRunnerCancellationTests {
  private let fixture: VerifyFixture
  private let cancellation = CancellationSwitch()

  init() throws {
    fixture = try VerifyFixture(
      bridge: VerifyFixture.bridge(running: "true"),
    )
  }

  /// A scripted command that is cancelled while it runs, having printed `text`.
  private func stopped(printing text: String = "") -> ScriptedProcessSupervisor.Step {
    { [cancellation] _ in
      cancellation.raise()

      return ScriptedProcessSupervisor.ended(
        .cancelled,
        text,
      )
    }
  }

  @Test
  func `a cancellation while a command runs seals the run as interrupted, with no verdicts`()
    async throws
  {
    let verified = try await fixture.run(
      fixture.runner(
        transformer: fixture.answering(),
        cancellation: cancellation,
        supervisor: ScriptedProcessSupervisor(inOrder: [stopped()]),
      ),
    )
    let history = try fixture.history()

    #expect(verified.isCancelled)
    #expect(verified.results.isEmpty)
    #expect(verified.notes == ["cancelled before judging; sources not processed: unit-tests"])
    #expect(history.runs.count == 1)
    #expect(history.runs.first?.termination == .interrupted)
    #expect(history.runs.first?.results.isEmpty == true)
  }

  @Test
  func `what the stopped command printed is kept`() async throws {
    let verified = try await fixture.run(
      fixture.runner(
        cancellation: cancellation,
        supervisor: ScriptedProcessSupervisor(inOrder: [stopped(printing: "begun\n")]),
      ),
    )
    let run = try #require(verified.runIdentifier)

    #expect(try fixture.read(".use-cases/runs/\(run)/outputs/unit-tests/console.txt") == "begun\n")
  }

  @Test
  func `the commands after the one that was stopped never start`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      """
      schema_version: 1
      validations:
        - id: first
          report: f.txt
          run: [sh, -c, 'echo first', sh, "{report}"]
          transformer: junit
        - id: second
          report: s.txt
          run: [sh, -c, 'echo second', sh, "{report}"]
          transformer: junit

      """,
    )

    // A second command would be asked of the supervisor, which has nothing scripted for it.
    let supervisor = ScriptedProcessSupervisor(inOrder: [stopped()])
    let verified = try await fixture.run(
      fixture.runner(
        cancellation: cancellation,
        supervisor: supervisor,
      ),
    )

    #expect(verified.isCancelled)
    #expect(
      verified.notes == ["cancelled before judging; sources not processed: first, second"],
    )
    #expect(await supervisor.requests.map { $0.arguments[2] } == ["echo first"])
  }

  /// A runner whose first command ends with `first` and raises the cancellation as it ends.
  private func cancellingAfter(_ first: RanCommand) -> VerifyRunner {
    fixture.runner(
      cancellation: cancellation,
      executor: MockRunCommandExecutor { [cancellation] _, _ in
        cancellation.raise()

        return .ran(first)
      },
    )
  }

  private func writeTwoValidations() throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      """
      schema_version: 1
      validations:
        - id: first
          report: f.txt
          run: [sh, -c, 'true', sh, "{report}"]
          transformer: junit
        - id: second
          report: s.txt
          run: [sh, -c, 'true', sh, "{report}"]
          transformer: junit

      """,
    )
  }

  @Test
  func `a command that ended before the cancellation keeps its own result`() async throws {
    try writeTwoValidations()

    let verified = try await fixture.run(
      cancellingAfter(
        RanCommand(
          command: ["sh", "first"],
          failure: nil,
          exitCode: 4,
          seconds: 1.5,
        ),
      ),
    )
    let sources = try #require(verified.manifest?.sources)

    #expect(verified.isCancelled)
    #expect(sources.map(\.identifier.text) == ["first", "second"])
    #expect(sources.first?.exitCode == 4)
    #expect(sources.first?.seconds == 1.5)
    #expect(sources.first?.command == ["sh", "first"])
    #expect(sources.last?.command == nil)
    #expect(
      verified.notes == ["cancelled before judging; sources not processed: first, second"],
    )
  }

  @Test
  func `a command that ended badly before the cancellation keeps its run error`() async throws {
    try writeTwoValidations()

    let verified = try await fixture.run(
      cancellingAfter(
        RanCommand(
          command: ["sh", "first"],
          failure: "command terminated abnormally (signal 9)",
          exitCode: nil,
          seconds: 0.5,
        ),
      ),
    )

    #expect(verified.errors == ["first: command terminated abnormally (signal 9)"])
    #expect(verified.manifest?.sources.first?.error == "command terminated abnormally (signal 9)")
  }

  @Test
  func `a cancellation before the request began opens no run`() async throws {
    await #expect(throws: VerifyError.cancelled) {
      try await fixture.run(fixture.runner(cancellation: MockCancellation.always))
    }

    #expect(fixture.runs().isEmpty)
  }

  @Test
  func `a cancellation after the last command is sealed as interrupted too`() async throws {
    let executor = MockRunCommandExecutor { [cancellation] _, _ in
      cancellation.raise()

      return .ran(
        RanCommand(
          command: ["true"],
          failure: nil,
          exitCode: 0,
          seconds: 0,
        ),
      )
    }

    let verified = try await fixture.run(
      fixture.runner(
        transformer: fixture.answering(),
        cancellation: cancellation,
        executor: executor,
      ),
    )

    #expect(verified.isCancelled)
    #expect(verified.results.isEmpty)
    #expect(try fixture.history().runs.first?.termination == .interrupted)
  }

  @Test
  func `a cancellation while the code is noted writes no run at all`() async throws {
    let observer = cancellation
    let opener = MockRunOpener(starter: fixture.starter()) {
      observer.raise()
    }
    let runner = VerifyRunner(
      opener: opener,
      store: .success(fixture.store),
      finishPoint: .success(
        fixture.finishPoint(
          runner: MockTransformerRunner(answers: []),
          cancellation: observer,
        ),
      ),
      executor: MockRunCommandExecutor { _, _ in
        Issue.record("no command may start")

        return .cancelled
      },
      cancellation: ObservedCancellationScope(makeObserver: { observer }),
    )

    await #expect(throws: VerifyError.cancelled) {
      try await fixture.run(runner)
    }

    #expect(fixture.runs().isEmpty)
  }
}
