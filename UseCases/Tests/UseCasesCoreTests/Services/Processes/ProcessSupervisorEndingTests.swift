import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct ProcessSupervisorEndingTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test(arguments: [0, 1, 2, 42, 126, 127, 255] as [Int32])
  func `a command that ends by itself reports its exit code`(code: Int32) async throws {
    let run = try await fixture.run("exit \(code)")

    #expect(run.termination == .exited(code))
  }

  @Test(arguments: [9, 15, 1] as [Int32])
  func `a command killed by a signal reports that signal`(signal: Int32) async throws {
    let run = try await fixture.run("kill -\(signal) $$")

    #expect(run.termination == .signaled(signal))
  }

  @Test
  func `a command killed by a signal reads as an abnormal termination`() async throws {
    let run = try await fixture.run("kill -9 $$")

    #expect(run.termination.runErrorWords == "command terminated abnormally (signal 9)")
  }

  @Test
  func `a background child holding the output open does not hold the run up`() async throws {
    let hold = try fixture.hold()
    defer {
      hold.release()
    }
    let holders = PipeHolders()
    let supervisor = fixture.supervisor(
      clock: ContinuousClock(),
      holders: holders,
    )
    let childScript = try fixture.script("child.sh", hold.shellText())

    let request = fixture.request(
      "\(childScript) & echo done",
      timeout: ProcessFixture.timeLimitNoTestReaches,
    )

    let run = try await supervisor.run(request)

    let child = try await ProcessFixture.processIdentifier(
      heldBy: hold,
      unless: {
        await holders.allGone()
      },
      failing: "the child ended before it was held",
    )
    #expect(run.termination == .exited(0))
    #expect(run.console.text == "done\n")
    // The run ended while the child, held until now, still holds the capture open.
    #expect(ProcessFixture.exists(child))

    hold.release()
    await holders.allGone()
  }

  @Test
  func `each run is its own: nothing carries from one command to the next`() async throws {
    let first = try await fixture.run("echo first; exit 3")
    let second = try await fixture.run("echo second")

    #expect(first.termination == .exited(3))
    #expect(first.console.text == "first\n")
    #expect(second.termination == .exited(0))
    #expect(second.console.text == "second\n")
  }
}
