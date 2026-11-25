import Foundation
import Testing
@testable import UseCasesCore

/// What the runner asks of the watcher it is given.
struct CommandRunnerWatcherTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test
  func `a program is watched with no time limit, and ends as the watcher finds`() async throws {
    let reaper = ProcessReaper()
    let clock = ContinuousClock()
    let watcher = SpyProcessWatching(
      watchingThrough: ProcessWatcher(
        cancellation: NeverCancelled(),
        clock: clock,
        pollInterval: .milliseconds(1),
        reaper: reaper,
        stopper: ProcessGroupStopper(
          clock: clock,
          grace: ProcessFixture.terminationGrace,
          pollInterval: .milliseconds(1),
          reaper: reaper,
        ),
      ),
    )

    let outcome = try await CommandRunner(watcher: watcher).run(
      CommandInvocation(
        arguments: ["/bin/sh", "-c", "exit 3"],
        workingDirectory: fixture.directory.url,
        standardInput: nil,
      ),
    )

    let watches = await watcher.watches

    #expect(outcome.ending == .exited(3))
    #expect(watches.count == 1)
    #expect(watches.first?.timeout == nil)
    #expect((watches.first?.leader ?? 0) > 1)
  }
}
