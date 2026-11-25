import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct CommandRunnerLifelineTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  private func invocation(
    _ script: String,
    lifeline: Int32?,
  ) -> CommandInvocation {
    CommandInvocation(
      arguments: ["/bin/sh", "-c", script],
      workingDirectory: fixture.directory.url,
      lifeline: lifeline,
    )
  }

  @Test
  func `a program is handed the lifeline as its third descriptor, named in its environment`(
  ) async throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }
    pipe.closeWriteEnd()

    let outcome = try await CommandRunner().run(
      invocation(
        "[ -p /dev/fd/3 ] && echo pipe:$USE_CASES_LIFELINE_FD && cat <&3; echo end",
        lifeline: pipe.readEnd,
      ),
    )

    // The pipe has no writer left, so reading it ends at once.
    #expect(outcome.standardOutput == "pipe:3\nend\n")
    #expect(outcome.ending == .exited(0))
  }

  @Test
  func `the descriptor the program is handed is the very pipe, not a copy of its words`(
  ) async throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
      pipe.closeWriteEnd()
    }
    write(pipe.writeEnd, "hello\n", 6)

    let outcome = try await CommandRunner().run(
      invocation("read line <&3; echo got:$line", lifeline: pipe.readEnd),
    )

    #expect(outcome.standardOutput == "got:hello\n")
  }

  @Test
  func `a program given no lifeline has no third descriptor`() async throws {
    let outcome = try await CommandRunner().run(
      invocation("(echo no >&3) 2>/dev/null || echo closed", lifeline: nil),
    )

    #expect(outcome.standardOutput == "closed\n")
  }

  @Test
  func `the environment names the descriptor a lifeline is handed as, or carries none`() {
    let base = ["PATH": "/usr/bin", ProcessLifeline.variable: "7"]

    #expect(
      ProcessLauncher.environment(of: base, lifeline: 12).sorted()
        == ["PATH=/usr/bin", "USE_CASES_LIFELINE_FD=3"],
    )
    #expect(ProcessLauncher.environment(of: base, lifeline: nil) == ["PATH=/usr/bin"])
    #expect(
      ProcessLauncher.environment(of: ["PATH": "/usr/bin"], lifeline: nil) == ["PATH=/usr/bin"],
    )
  }

  @Test
  func `no other descriptor of this process reaches the program`() async throws {
    // The pipe's ends are parked above 200, where a shell keeps none of its own: bash holds a
    // descriptor of its own at 10, and the lifeline is handed as 3.
    let pipe = TestPipe()
    let readEnd = fcntl(pipe.readEnd, F_DUPFD, 200)
    let writeEnd = fcntl(pipe.writeEnd, F_DUPFD, 200)
    pipe.closeReadEnd()
    pipe.closeWriteEnd()
    defer {
      close(readEnd)
      close(writeEnd)
    }

    #expect(readEnd >= 200)
    #expect(writeEnd >= 200)

    let outcome = try await CommandRunner().run(
      invocation(
        """
        for fd in 4 5 6 7 8 9 \(readEnd) \(writeEnd); do
          (: <&$fd) 2>/dev/null && echo open:$fd
        done
        echo done
        """,
        lifeline: readEnd,
      ),
    )

    #expect(outcome.standardOutput == "done\n")
  }
}
