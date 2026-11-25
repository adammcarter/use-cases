import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// What the supervisor asks of the watcher it is given.
struct ProcessSupervisorWatcherTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  private func supervisor(
    launcher: any ProcessLaunching,
    watcher: any ProcessWatching,
  ) -> ProcessSupervisor<TestClock> {
    ProcessSupervisor(
      launcher: launcher,
      watcher: watcher,
      makeCapture: { () throws(ProcessSupervisingError) -> any ConsoleCapturing in
        MockConsoleCapture()
      },
    )
  }

  @Test
  func `the command that was launched is watched with the time the request gave`() async throws {
    let watcher = SpyProcessWatching(ending: .exited(3))
    let supervisor = supervisor(
      launcher: MockProcessLauncher.starting(777),
      watcher: watcher,
    )

    let run = try await supervisor.run(fixture.request("true", timeout: .seconds(30)))

    #expect(run.termination == .exited(3))
    #expect(run.wasLaunched)
    #expect(
      await watcher.watches == [SpyProcessWatching.Watch(leader: 777, timeout: .seconds(30))],
    )
  }

  @Test
  func `a run the watcher says was cancelled starts nothing`() async throws {
    let watcher = SpyProcessWatching(isCancelled: true)
    let supervisor = supervisor(
      launcher: MockProcessLauncher.refusing,
      watcher: watcher,
    )

    let run = try await supervisor.run(fixture.request("true"))

    #expect(run.termination == .cancelled)
    #expect(!run.wasLaunched)
    #expect(await watcher.watches.isEmpty)
  }
}
