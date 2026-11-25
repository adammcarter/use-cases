import Foundation
import Testing
@testable import UseCasesCore

/// The supervisor's decisions, asked of doubles, so the moments a real process cannot be made to
/// hit on demand are hit exactly.
struct ProcessSupervisorSeamTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test
  func `a command that has run out of time is stopped and reported as timed out`() async throws {
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper.running,
      stopper: stopper,
    )

    let run = try await supervisor.run(fixture.request("true", timeout: .zero))

    #expect(run.termination == .timedOut(after: .zero))
    #expect(await stopper.stopped == [777])
  }

  @Test
  func `a command that ended just as its time ran out keeps its own ending`() async throws {
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper(answers: [.success(nil), .success(.exited(3))]),
      stopper: stopper,
    )

    let run = try await supervisor.run(fixture.request("true", timeout: .zero))

    #expect(run.termination == .exited(3))
    #expect(await stopper.stopped.isEmpty)
  }

  @Test
  func `a command that cannot be asked about is stopped before the failure is passed on`()
    async throws
  {
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper(answers: [.success(nil), .failure(.waitFailed(reason: "gone"))]),
      stopper: stopper,
    )

    await #expect(throws: ProcessSupervisingError.waitFailed(reason: "gone")) {
      try await supervisor.run(fixture.request("true"))
    }
    #expect(await stopper.stopped == [777])
  }

  @Test
  func `a command that cannot be asked about at the first look is stopped too`() async throws {
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.starting(777),
      reaper: MockProcessReaper(answers: [.failure(.waitFailed(reason: "gone"))]),
      stopper: stopper,
    )

    await #expect(throws: ProcessSupervisingError.waitFailed(reason: "gone")) {
      try await supervisor.run(fixture.request("true"))
    }
    #expect(await stopper.stopped == [777])
  }

  @Test
  func `a command that cannot be launched is never asked about or stopped`() async throws {
    let stopper = MockProcessGroupStopper()
    let supervisor = fixture.supervisor(
      launcher: MockProcessLauncher.refusing,
      reaper: MockProcessReaper(answers: [.failure(.waitFailed(reason: "not asked"))]),
      stopper: stopper,
    )

    await #expect(throws: ProcessSupervisingError.self) {
      try await supervisor.run(fixture.request("true"))
    }
    #expect(await stopper.stopped.isEmpty)
  }
}
