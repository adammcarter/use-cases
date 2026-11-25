import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// Nothing here waits on a timer: a command that is running is held until the test lets it go, the
/// cancellation comes once the test has heard it is held, and the stop is waited for until the
/// group is gone. A group that was not stopped is still held, so it is never mistaken for one that
/// ended by itself.
struct ProcessSupervisorCancellationTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test
  func `a cancellation already raised starts nothing`() async throws {
    let supervisor = fixture.supervisor(cancellation: MockCancellation.always)

    let run = try await supervisor.run(fixture.request("touch started"))

    #expect(run.termination == .cancelled)
    #expect(run.console == .empty)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.location(of: "started").path))
  }

  @Test
  func `a cancellation while the command runs stops its whole group`() async throws {
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let cancellation = CancellationSwitch()
    let holders = PipeHolders()
    let supervisor = fixture.supervisor(
      clock: ContinuousClock(),
      cancellation: cancellation,
      holders: holders,
    )
    let childScript = try fixture.script("child.sh", hold.shellText())
    let request = fixture.request(
      "echo started; \(childScript) & wait",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    let child = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    cancellation.raise()

    let run = try await running.value
    #expect(run.termination == .cancelled)
    #expect(run.console.text == "started\n")
    #expect(!ProcessFixture.exists(child))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `cancelling the task while the command runs stops its whole group`() async throws {
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let holders = PipeHolders()
    // Once armed, the next look the supervisor takes cancels its own task, as a caller would.
    let observer = TaskCancellingCancellation()
    let supervisor = fixture.supervisor(
      clock: ContinuousClock(),
      cancellation: observer,
      holders: holders,
    )
    let childScript = try fixture.script("child.sh", hold.shellText())
    let request = fixture.request(
      "\(childScript) & wait",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    let child = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    await observer.arm()

    let run = try await running.value
    #expect(run.termination == .cancelled)
    #expect(!ProcessFixture.exists(child))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `a task cancelled before the command starts launches nothing`() async throws {
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.refusing,
      reaper: MockProcessReaper.running,
      stopper: MockProcessGroupStopper(),
    )
    let request = fixture.request("true")

    let task = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }

      return try? await supervisor.run(request)
    }
    let run = try #require(await task.value)

    #expect(run.termination == .cancelled)
    #expect(run.console == .empty)
  }

  @Test
  func `a cancellation stops the group of the command that was started`() async throws {
    let cancellation = CancellationSwitch()
    let stopper = MockProcessGroupStopper()
    // The run is cancelled once the command is going.
    let supervisor = fixture.supervisor(
      cancellation: cancellation,
      launcher: MockProcessLauncher.starting(
        777,
        raising: cancellation,
      ),
      reaper: MockProcessReaper.running,
      stopper: stopper,
    )

    let run = try await supervisor.run(fixture.request("true"))

    #expect(run.termination == .cancelled)
    #expect(await stopper.stopped == [777])
  }

  @Test
  func `a command that ends before the cancellation arrives keeps its own ending`() async throws {
    let supervisor = fixture.supervisor(cancellation: MockCancellation.never)

    let run = try await supervisor.run(fixture.request("exit 4"))

    #expect(run.termination == .exited(4))
  }
}
