import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// The commands of `verify --run` (chapter 14). What the executor does with a command is proven
/// against a scripted supervisor on a clock the test moves; that the console reaches the store
/// and that a launch failure names its program are proven on real processes, through the real
/// supervisor, with commands that end by themselves.
struct RunCommandExecutorTests {
  /// The command every scripted test's bridge stores, `{report}` and all.
  private static let stored = ["sh", "-c", "true", "sh", "{report}"]

  private let fixture: VerifyFixture
  private let clock = TestClock()

  init() throws {
    fixture = try VerifyFixture(
      bridge: VerifyFixture.bridge(running: "true"),
    )
  }

  @Test
  func `a command that ends by itself has its exit code and how long it ran`() async throws {
    let executed = try await execution(
      answering: [taking(.milliseconds(2500), ScriptedProcessSupervisor.exited(3))],
    )
    let done = executed.execution
    let command = try ran(done)

    #expect(command.exitCode == 3)
    #expect(command.failure == nil)
    #expect(command.command == Self.stored)
    #expect(command.seconds == 2.5)
  }

  @Test
  func `report is the absolute path of the validation's report in this run`() async throws {
    let executed = try await execution(
      answering: [VerifyFixture.writingReport("wrote")],
    )
    let run = executed.run
    let requests = executed.requests
    let request = try #require(requests.first)
    let expected = fixture.runFolder(run.identifier.text)
      .appendingPathComponent("reports/unit-tests/unit.xml").path

    #expect(request.reportPath == expected)
    #expect(request.reportPath?.hasPrefix("/") == true)
    #expect(
      try fixture.read(".use-cases/runs/\(run.identifier.text)/reports/unit-tests/unit.xml")
        == "wrote",
    )
  }

  /// Real: what a real command printed, on both streams, is what reaches the store.
  @Test
  func `stdout and stderr are kept together, in the order they were written`() async throws {
    let (_, run) = try await realExecution(of: "echo one; echo two >&2; echo three")

    #expect(try console(of: run) == "one\ntwo\nthree\n")
  }

  /// That the command then reads an empty input is the supervisor's part, proven on a real
  /// process by `ProcessSupervisorSurroundingsTests` ("standard input is empty").
  @Test
  func `the command gets no input`() async throws {
    let executed = try await execution(
      answering: [ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))],
    )
    let requests = executed.requests

    // The command goes to the supervisor as stored, and a request carries no input to give it.
    #expect(
      requests == [
        ProcessRequest(
          arguments: Self.stored,
          workingDirectory: fixture.workspace,
          reportPath: requests.first?.reportPath,
          timeout: ProcessTimeout.runCommandDefault,
        ),
      ],
    )
  }

  @Test
  func `the command starts in the workspace root, and in working_dir when the validation has one`()
    async throws
  {
    try fixture.freshness.write("sub/keep.txt", "x")

    let root = try await execution(
      answering: [ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))],
    )
    let nested = try await execution(
      lines: ["working_dir: sub"],
      answering: [ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))],
    )

    #expect(root.requests.map(\.workingDirectory.path) == [fixture.workspace.path])
    #expect(
      nested.requests.map(\.workingDirectory.standardizedFileURL.path)
        == [fixture.workspace.appendingPathComponent("sub").standardizedFileURL.path],
    )
  }

  /// That the environment then reaches the command unchanged is the supervisor's part, proven
  /// on a real process by `ProcessSupervisorSurroundingsTests` ("the environment of this process
  /// is passed on unchanged", "no variable is added or taken away").
  @Test
  func `the command gets the environment of the process unchanged`() async throws {
    let executed = try await execution(
      answering: [ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.exited(0))],
    )
    let requests = executed.requests
    let request = try #require(requests.first)

    // Nothing of the environment is chosen here: the arguments are passed as stored, with no
    // variable set in front of them and no shell around them.
    #expect(request.arguments == Self.stored)
  }

  @Test
  func `a command that is killed by a signal is a failure, not an exit code`() async throws {
    let executed = try await execution(
      answering: [
        ScriptedProcessSupervisor.answering(
          ScriptedProcessSupervisor.ended(
            .signaled(9),
            "before\n",
          ),
        ),
      ],
    )
    let done = executed.execution
    let run = executed.run
    let command = try ran(done)

    #expect(command.failure == "command terminated abnormally (signal 9)")
    #expect(command.exitCode == nil)
    #expect(try console(of: run) == "before\n")
  }

  @Test
  func `a command that outlives its timeout is stopped and is a failure`() async throws {
    let executed = try await execution(
      lines: ["timeout_seconds: 1"],
      answering: [
        { request in
          ScriptedProcessSupervisor.ended(
            .timedOut(after: request.timeout),
            "started\n",
          )
        },
      ],
    )
    let done = executed.execution
    let run = executed.run
    let requests = executed.requests
    let command = try ran(done)

    #expect(requests.map(\.timeout) == [.seconds(1)])
    #expect(command.failure == "command timed out after 1 seconds")
    #expect(command.exitCode == nil)
    #expect(try console(of: run) == "started\n")
  }

  @Test
  func `a command that cannot be launched is a failure that says why`() async throws {
    let executed = try await execution(
      answering: [
        taking(
          .milliseconds(250),
          .failure(.couldNotLaunch(reason: "No such file or directory")),
        ),
      ],
    )
    let done = executed.execution
    let run = executed.run
    let command = try ran(done)

    #expect(command.failure == "command could not be launched: sh: No such file or directory")
    #expect(command.exitCode == nil)
    #expect(command.seconds == 0.25)
    #expect(!hasOutputs(run))
  }

  @Test
  func `a validation with no run command has nothing to run`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(lines: ["report: unit.xml"]),
    )

    let executed = try await execution(answering: [])
    let done = executed.execution
    let run = executed.run
    let requests = executed.requests

    #expect(done == .ran(.missing))
    #expect(requests.isEmpty)
    #expect(RanCommand.missing.command == nil)
    #expect(RanCommand.missing.failure?.hasPrefix("no run command: run its tests yourself") == true)
    #expect(!hasOutputs(run))
  }

  @Test
  func `a cancellation while the command runs stops it and keeps what it printed`() async throws {
    let executed = try await execution(
      answering: [
        ScriptedProcessSupervisor.answering(
          ScriptedProcessSupervisor.ended(
            .cancelled,
            "started\n",
          ),
        ),
      ],
    )
    let done = executed.execution
    let run = executed.run

    #expect(done == .cancelled)
    #expect(try console(of: run) == "started\n")
  }

  @Test
  func `a cancellation before the command starts runs nothing and keeps no console`() async throws {
    let executed = try await execution(
      answering: [
        ScriptedProcessSupervisor.answering(
          ScriptedProcessSupervisor.ended(
            .cancelled,
            wasLaunched: false,
          ),
        ),
      ],
    )
    let done = executed.execution
    let run = executed.run

    #expect(done == .cancelled)
    #expect(!hasOutputs(run))
  }

  /// The bound itself is the supervisor's, proven on real processes by
  /// `ProcessSupervisorConsoleTests`; what it kept, marker and all, is what the run keeps.
  @Test
  func `no more than a megabyte of console is kept, with a marker for the rest`() async throws {
    let half = String(
      repeating: "x",
      count: 512 * 1024,
    )
    let kept = half + "\n[... 1951425 bytes not kept ...]\n" + half + "\n"
    let executed = try await execution(
      answering: [
        ScriptedProcessSupervisor.answering(
          .success(
            ProcessRun(
              termination: .exited(0),
              console: ProcessConsole(
                text: kept,
                omittedByteCount: 1_951_425,
              ),
              wasLaunched: true,
            ),
          ),
        ),
      ],
    )
    let run = executed.run
    let text = try console(of: run)

    #expect(text == kept)
    #expect(text.contains("bytes not kept"))
    #expect(text.utf8.count < 1024 * 1024 + 100)
  }

  @Test
  func `a command launched and silent before it was cancelled has an empty console`()
    async throws
  {
    let executed = try await execution(
      answering: [
        ScriptedProcessSupervisor.answering(ScriptedProcessSupervisor.ended(.cancelled)),
      ],
    )
    let done = executed.execution
    let run = executed.run

    #expect(done == .cancelled)
    #expect(try console(of: run).isEmpty)
  }

  /// Real: the reason comes from the real launcher, and the program from the stored command.
  @Test
  func `a launch failure names the program that could not be launched`() async throws {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(
        lines: ["report: unit.xml", "run: [no-such-program-anywhere, --flag]"],
      ),
    )

    let (done, run) = try await realExecution()
    let command = try ran(done)

    #expect(
      command.failure?.hasPrefix("command could not be launched: no-such-program-anywhere: ")
        == true,
    )
    #expect(!hasOutputs(run))
  }

  @Test
  func `how long a command ran is rounded to the millisecond`() async throws {
    let executed = try await execution(
      answering: [
        taking(.nanoseconds(1_234_567_891), ScriptedProcessSupervisor.exited(0)),
      ],
    )
    let done = executed.execution

    #expect(try ran(done).seconds == 1.235)
  }
}

extension RunCommandExecutorTests {
  /// Rewrites the bridge settings so that `unit-tests` runs `true` with these extra lines, and
  /// executes it, the supervisor answering with `steps`.
  private func execution(
    lines: [String] = [],
    answering steps: [ScriptedProcessSupervisor.Step],
  ) async throws -> Executed {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      VerifyFixture.bridge(
        running: "true",
        lines: lines,
      ),
    )

    return try await execution(answering: steps)
  }

  private func execution(
    answering steps: [ScriptedProcessSupervisor.Step],
  ) async throws -> Executed {
    let supervisor = ScriptedProcessSupervisor(inOrder: steps)
    let (done, run) = try await execution(
      on: RunCommandExecutor(
        supervisor: supervisor,
        writer: .success(fixture.store.writer),
        clock: clock,
      ),
    )

    return await Executed(
      execution: done,
      run: run,
      requests: supervisor.requests,
    )
  }

  /// Rewrites the bridge settings so that `unit-tests` runs `script`, and runs it for real.
  private func realExecution(
    of script: String,
  ) async throws -> (execution: CommandExecution, run: OpenRun) {
    try fixture.freshness.write(
      "use-cases-bridge.yml",
      VerifyFixture.bridge(running: script),
    )

    return try await realExecution()
  }

  private func realExecution() async throws -> (execution: CommandExecution, run: OpenRun) {
    try await execution(
      on: RunCommandExecutor(
        supervisor: ProcessSupervisor(cancellation: MockCancellation.never),
        writer: .success(fixture.store.writer),
      ),
    )
  }

  private func execution(
    on executor: some RunCommandExecuting,
  ) async throws -> (execution: CommandExecution, run: OpenRun) {
    let opened = try fixture.openedRun()

    defer {
      opened.lock.release()
    }

    let validation = try #require(opened.selected.first)
    let done = try await executor.execute(
      validation,
      in: opened.run,
    )

    return (done, opened.run)
  }

  /// A scripted command that runs for `duration` on the test's clock and then ends with
  /// `answer`.
  private func taking(
    _ duration: Duration,
    _ answer: Result<ProcessRun, ProcessSupervisingError>,
  ) -> ScriptedProcessSupervisor.Step {
    { [clock] _ in
      await clock.advance(by: duration)

      return answer
    }
  }

  private func ran(_ execution: CommandExecution) throws -> RanCommand {
    guard case let .ran(command) = execution else {
      throw Failure.notRan
    }

    return command
  }

  private func console(of run: OpenRun) throws -> String {
    try fixture.read(".use-cases/runs/\(run.identifier.text)/outputs/unit-tests/console.txt")
  }

  private func hasOutputs(_ run: OpenRun) -> Bool {
    FileManager.default.fileExists(
      atPath: fixture.runFolder(run.identifier.text).appendingPathComponent("outputs").path,
    )
  }

  private enum Failure: Error {
    case notRan
  }

  /// One scripted execution: how it came out, the run it was in, and what the supervisor was
  /// asked.
  private struct Executed {
    let execution: CommandExecution
    let run: OpenRun
    let requests: [ProcessRequest]
  }
}
