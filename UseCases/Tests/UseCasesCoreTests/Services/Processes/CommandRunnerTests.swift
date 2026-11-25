import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct CommandRunnerTests {
  private let fixture: ProcessFixture

  private var folder: TemporaryDirectory {
    fixture.directory
  }

  init() throws {
    fixture = try ProcessFixture()
  }

  /// `script` run by `/bin/sh -c` in the test's folder.
  private func invocation(
    _ script: String,
    standardInput: String? = nil,
  ) -> CommandInvocation {
    CommandInvocation(
      arguments: ["/bin/sh", "-c", script],
      workingDirectory: folder.url,
      standardInput: standardInput,
    )
  }

  @Test
  func `stdout and stderr come back apart`() async throws {
    let outcome = try await CommandRunner().run(invocation("echo out; echo err >&2"))

    #expect(outcome.standardOutput == "out\n")
    #expect(outcome.standardError == "err\n")
    #expect(outcome.ending == .exited(0))
  }

  @Test(arguments: [0, 1, 2, 130])
  func `the exit code is how it ended`(code: Int32) async throws {
    let outcome = try await CommandRunner().run(invocation("exit \(code)"))

    #expect(outcome.ending == .exited(code))
  }

  @Test
  func `a program killed by a signal ended by that signal`() async throws {
    let outcome = try await CommandRunner().run(invocation("kill -9 $$"))

    #expect(outcome.ending == .signaled(9))
  }

  @Test
  func `the program starts in the folder it is given`() async throws {
    let outcome = try await CommandRunner().run(invocation("pwd"))

    #expect(outcome.standardOutput == folder.url.path + "\n")
  }

  @Test(arguments: ["", "one line", "two\nlines\n", "caf\u{E9} \u{1F600}", "{\"a\": [1, 2]}"])
  func `the text given is the program's standard input, from a file`(text: String) async throws {
    let outcome = try await CommandRunner().run(invocation("cat", standardInput: text))

    #expect(outcome.standardOutput == text)
  }

  @Test
  func `a program given no input reads nothing, and is not left waiting for it`() async throws {
    let outcome = try await CommandRunner().run(invocation("cat"))

    #expect(outcome.standardOutput.isEmpty)
    #expect(outcome.ending == .exited(0))
  }

  @Test(arguments: [1_048_576, 1_048_577, 3_000_000])
  func `output of any size comes back whole, never cut`(count: Int) async throws {
    let fill = "head -c \(count) /dev/zero | tr '\\0'"
    let script = "\(fill) x; \(fill) y >&2"

    let outcome = try await CommandRunner().run(invocation(script))

    #expect(outcome.standardOutput == String(repeating: "x", count: count))
    #expect(outcome.standardError == String(repeating: "y", count: count))
  }

  @Test
  func `a cancellation stops the whole group and answers cancelled`() async throws {
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let cancellation = CancellationSwitch()
    let runner = CommandRunner(
      terminationGrace: ProcessFixture.terminationGrace,
      pollInterval: .milliseconds(1),
      cancellation: cancellation,
      clock: ContinuousClock(),
    )
    let childScript = try fixture.script("child.sh", hold.shellText())
    let running = invocation("echo started; \(childScript) & wait")

    let runs = Task {
      try await runner.run(running)
    }

    let child = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: runs,
    )
    cancellation.raise()

    let outcome = try await runs.value
    #expect(outcome.ending == .cancelled)
    #expect(outcome.standardOutput == "started\n")
    #expect(!ProcessFixture.exists(child))
  }

  @Test
  func `a program is looked at again only once the clock it was given moves on`() async throws {
    let clock = TestClock()
    let cancellation = CountingCancellation()
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    // Every process of the program holds the lifeline, so when its writers have gone, every
    // process has ended.
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }
    let runner = CommandRunner(
      terminationGrace: ProcessFixture.terminationGrace,
      pollInterval: .milliseconds(1),
      cancellation: cancellation,
      clock: clock,
    )
    let childScript = try fixture.script("child.sh", hold.shellText())
    let running = CommandInvocation(
      arguments: ["/bin/sh", "-c", childScript],
      workingDirectory: folder.url,
      lifeline: pipe.writeEnd,
    )

    let runs = Task {
      try await runner.run(running)
    }

    _ = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: runs,
    )
    pipe.closeWriteEnd()

    // Between its first look and its second, the watcher waits on the clock it was given.
    let isParkedFirst = await EventRace.isFirst {
      await clock.nextSleep()
    } before: {
      await cancellation.askedTwice.wait()
    }
    try #require(isParkedFirst)

    hold.release()
    await pipe.writersGone()
    await Self.advance(
      clock,
      untilEnded: runs,
    )

    let outcome = try await runs.value
    #expect(outcome.ending == .exited(0))
  }

  /// Moves `clock` on until the run ends. A program whose every process has closed its
  /// descriptors can be a moment from being told apart as ended by the system, so a look that
  /// still finds it running, and waits on the clock again, is answered by moving the clock once
  /// more; the watcher is parked on the clock each time it is moved.
  private static func advance(
    _ clock: TestClock,
    untilEnded runs: Task<CommandOutcome, any Error>,
  ) async {
    @Sendable
    func parks() async {
      await clock.nextSleep()
    }

    @Sendable
    func ends() async {
      _ = await runs.result
    }

    // Not a wait on time: every turn waits for an event, the watcher parking on the clock again,
    // and the loop ends when the run does. A child closes its descriptors a moment before the
    // system lets it be collected, so one look after they close can still find it running.
    repeat {
      await clock.advance(by: .milliseconds(1))
    } while await !EventRace.isFirst(ends, before: parks)
  }

  @Test
  func `a task cancelled before the program starts starts nothing`() async throws {
    let touching = invocation("touch started")
    let task = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }

      return try await CommandRunner().run(touching)
    }

    let outcome = try await task.value

    #expect(outcome.ending == .cancelled)
    #expect(!FileManager.default.fileExists(atPath: folder.location(of: "started").path))
  }

  @Test
  func `a program that cannot be started is an error saying why`() async {
    let missing = CommandInvocation(
      arguments: ["/no/such/program"],
      workingDirectory: folder.url,
    )

    await #expect(throws: CommandRunningError.self) {
      try await CommandRunner().run(missing)
    }
  }

  @Test
  func `a folder that is not there is an error naming it`() async {
    let nowhere = CommandInvocation(
      arguments: ["/bin/sh", "-c", "true"],
      workingDirectory: folder.location(of: "nowhere"),
    )

    await #expect(throws: CommandRunningError.self) {
      try await CommandRunner().run(nowhere)
    }
  }
}
