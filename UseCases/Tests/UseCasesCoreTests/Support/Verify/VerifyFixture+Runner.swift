import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

extension VerifyFixture {
  /// A bridge file whose only validation, `unit-tests`, runs `script` with `sh -c`; the script
  /// gets the report path as `$1`.
  static func bridge(
    running script: String,
    lines: [String] = [],
  ) -> String {
    BridgeFileSamples.validation(
      lines: ["report: unit.xml", "run: [sh, -c, '\(script)', sh, \"{report}\"]"] + lines,
    )
  }

  /// A scripted command that writes `report` where `{report}` points, prints `console` and
  /// ends with `code`. A request with no report path, or a report that cannot be written, is a
  /// launch failure that says so.
  static func writingReport(
    _ report: String = "report\n",
    console: String = "",
    exitCode code: Int32 = 0,
  ) -> ScriptedProcessSupervisor.Step {
    { request in
      guard
        let path = request.reportPath,
        FileManager.default.createFile(
          atPath: path,
          contents: Data(report.utf8),
        )
      else {
        return .failure(.couldNotLaunch(reason: "no report written for \(request.arguments)"))
      }

      return ScriptedProcessSupervisor.ended(
        .exited(code),
        console,
      )
    }
  }

  /// A runner over the fixture's store whose commands are run by the real executor, timed on
  /// `clock` and handed to `supervisor`; `cancellation` watches the commands and the
  /// transformers, and `transformer` answers for them.
  func runner(
    transformer: any TransformerRunning = MockTransformerRunner(answers: []),
    cancellation: any CancellationObserving = MockCancellation.never,
    supervisor: any ProcessSupervising = ScriptedProcessSupervisor(inOrder: []),
    clock: TestClock = TestClock(),
  ) -> VerifyRunner {
    runner(
      transformer: transformer,
      cancellation: cancellation,
      executor: RunCommandExecutor(
        supervisor: supervisor,
        writer: .success(store.writer),
        clock: clock,
      ),
    )
  }

  /// A runner over the fixture's store whose commands are `executor`.
  func runner(
    transformer: any TransformerRunning = MockTransformerRunner(answers: []),
    cancellation: any CancellationObserving = MockCancellation.never,
    executor: any RunCommandExecuting,
  ) -> VerifyRunner {
    VerifyRunner(
      opener: starter(),
      store: .success(store),
      finishPoint: .success(
        finishPoint(
          runner: transformer,
          cancellation: cancellation,
        ),
      ),
      executor: executor,
      cancellation: ObservedCancellationScope(makeObserver: { cancellation }),
    )
  }

  /// Runs every validation of the fixture.
  func run(
    _ runner: VerifyRunner,
    only: [String] = [],
  ) async throws -> VerifiedRun {
    try await runner.run(
      VerifyRunRequest(only: only),
      in: resolved(),
      reloading: FixtureReloading(self),
    )
  }

  /// A transformer that gives the validation link of `unit-tests` this status.
  func answering(_ status: String = "pass") throws -> MockTransformerRunner {
    try MockTransformerRunner(
      answers: [.success(Self.response([linkKey(): status]))],
    )
  }

  /// Opens a run as `--run` does: held, with the lock the caller releases when it is done.
  func openedRun(only: [String] = []) throws -> OpenedRun {
    let starter = starter()
    let prepared = try starter.prepare(
      VerifyStartRequest(only: only),
      in: resolved(),
      openedBy: .run,
    )

    let opened = try starter.open(prepared)

    return try #require(opened)
  }
}
