import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ProcessSupervisorSessionTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test
  func `the command leads a session and a group of its own, named by its ID`() async throws {
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let supervisor = fixture.supervisor()
    let request = fixture.request(
      hold.shellText(),
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let running = Task {
      try await supervisor.run(request)
    }

    // Looked at while the command is held, and then it is let go.
    let command = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unlessEnded: running,
    )
    let session = getsid(command)
    let group = getpgid(command)
    let ours = getsid(0)
    hold.release()

    let run = try await running.value
    #expect(run.termination == .exited(0))
    #expect(session == command)
    #expect(group == command)
    // This process's session is not the command's.
    #expect(ours != command)
  }
}
