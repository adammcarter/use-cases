import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ProcessSupervisorSurroundingsTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  @Test
  func `the command starts in its working folder`() async throws {
    let run = try await fixture.run("pwd -P")

    #expect(run.console.text == "\(fixture.directory.url.path)\n")
  }

  @Test
  func `a nested working folder is entered with no cd`() async throws {
    try fixture.directory.makeDirectory("project/app")
    let nested = fixture.directory.location(of: "project/app")

    let run = try await fixture.supervisor().run(
      ProcessRequest(
        arguments: ["/bin/sh", "-c", "pwd -P"],
        workingDirectory: nested,
        reportPath: nil,
        timeout: .seconds(30),
      ),
    )

    #expect(run.console.text == "\(nested.path)\n")
  }

  @Test
  func `the environment of this process is passed on unchanged`() async throws {
    let environment = ProcessInfo.processInfo.environment
    let expected = "\(environment["PATH"] ?? "unset")|\(environment["HOME"] ?? "unset")"

    let run = try await fixture.run(#"printf '%s|%s' "$PATH" "${HOME-unset}""#)

    #expect(run.console.text == expected)
  }

  @Test
  func `no variable is added or taken away`() async throws {
    // The system's own env, started directly, so no shell adds or drops a variable.
    let environment = ProcessInfo.processInfo.environment
    let expected = Set(
      environment
        .filter { name, value in
          !name.hasPrefix("DYLD_") && !value.contains("\n")
        }
        .map { name, value in
          "\(name)=\(value)"
        },
    )

    let run = try await fixture.supervisor().run(
      ProcessRequest(
        arguments: ["/usr/bin/env"],
        workingDirectory: fixture.directory.url,
        reportPath: nil,
        timeout: .seconds(30),
      ),
    )

    // Whether a DYLD_ variable reaches a system program is the system's choice, not ours.
    let seen = Set(
      run.console.text
        .split(separator: "\n")
        .map(String.init)
        .filter { line in
          !line.hasPrefix("DYLD_")
        },
    )
    let hasMultilineValue = environment.values.contains { value in
      value.contains("\n")
    }

    // A value with a line break reads as several lines; then only what must be there is checked.
    if hasMultilineValue {
      #expect(expected.isSubset(of: seen))
    } else {
      #expect(seen == expected)
    }
  }

  @Test
  func `report is replaced in each argument with no quoting`() async throws {
    let path = "/runs/r 1/reports/it's here/unit.jsonl"
    let request = ProcessRequest(
      arguments: [
        "/bin/sh",
        "-c",
        #"printf '%s\n' "$1" "$2""#,
        "sh",
        "{report}",
        "out={report}.xml",
      ],
      workingDirectory: fixture.directory.url,
      reportPath: path,
      timeout: .seconds(30),
    )

    let run = try await fixture.supervisor().run(request)

    #expect(run.console.text == "\(path)\nout=\(path).xml\n")
    #expect(request.arguments.contains("{report}"))
  }

  @Test
  func `a shell variable in an argument is not expanded and a brace group is run by the shell`(
  ) async throws {
    let request = ProcessRequest(
      arguments: [
        "/usr/bin/printf",
        "%s|",
        "${HOME}",
        "{ }",
        "a || { b; }",
      ],
      workingDirectory: fixture.directory.url,
      reportPath: "/runs/r1/reports/unit",
      timeout: .seconds(30),
    )

    let run = try await fixture.supervisor().run(request)

    #expect(run.console.text == "${HOME}|{ }|a || { b; }|")
  }

  @Test
  func `a brace group inside a shell script the command names runs as written`() async throws {
    let request = ProcessRequest(
      arguments: ["/bin/sh", "-c", "false || { printf '%s' ran; }"],
      workingDirectory: fixture.directory.url,
      reportPath: "/runs/r1/reports/unit",
      timeout: .seconds(30),
    )

    let run = try await fixture.supervisor().run(request)

    #expect(run.console.text == "ran")
  }

  @Test
  func `standard input is empty`() async throws {
    let run = try await fixture.run(#"read line || echo "no input"; cat; echo end"#)

    #expect(run.console.text == "no input\nend\n")
  }

  @Test
  func `stdout and stderr share one capture in the order they were written`() async throws {
    let run = try await fixture.run("echo one; echo two >&2; echo three; echo four >&2")

    #expect(run.console.text == "one\ntwo\nthree\nfour\n")
  }

  @Test
  func `a descriptor open in this process is not open in the command`() async throws {
    try fixture.directory.write("held", "x")
    // Opened the plain way, so it would be inherited were nothing done about it. It is parked
    // above 200, where a shell keeps none of its own: bash holds a descriptor of its own at 10.
    let opened = open(fixture.directory.location(of: "held").path, O_RDONLY)
    let descriptor = fcntl(opened, F_DUPFD, 200)
    close(opened)
    defer {
      close(descriptor)
    }

    #expect(descriptor >= 200)

    let script = "if (true <&\(descriptor)) 2>/dev/null; then echo leaked; else echo closed; fi"

    let run = try await fixture.run(script)

    #expect(run.console.text == "closed\n")
  }

  @Test
  func `a signal this process ignores is back to its default in the command`() async throws {
    signal(SIGUSR2, SIG_IGN)
    defer {
      signal(SIGUSR2, nil)
    }

    let run = try await fixture.run("kill -USR2 $$; echo survived")

    #expect(run.termination == .signaled(SIGUSR2))
  }
}
