import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The capsule spawner against real processes. Every expectation here was
/// measured from node 26's `spawnSync` with the capsule runner's options on
/// this machine; the corpus covers the same ground through `runDemoCapsule`.
struct CapsuleProcessSpawnerTests {
  private static let path = "PATH=/usr/bin:/bin"

  @Test
  func `a program that exits reports its status and both streams`() throws {
    let directory = try TemporaryDirectory()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "printf out; printf err >&2; exit 3"],
      in: directory.url.path,
    ))

    #expect(outcome == CapsuleSpawnOutcome(
      exitStatus: 3,
      signal: nil,
      standardOutput: "out",
      standardError: "err",
      errorMessage: nil,
    ))
  }

  @Test(arguments: [
    ("definitely-missing-use-cases-tool", "ENOENT"),
    ("./missing", "ENOENT"),
    ("./plain.sh", "EACCES"),
    ("./no-shebang.sh", "ENOEXEC"),
    ("./bad-interpreter.sh", "ENOENT"),
    ("./folder", "EACCES"),
    ("folder", "ENOENT"),
    (String(repeating: "x", count: 255), "ENOENT"),
    (String(repeating: "x", count: 256), "ENAMETOOLONG"),
    ("./" + String(repeating: "x", count: 300), "ENAMETOOLONG"),
  ])
  func `a program that cannot start reports node's spawn error and no streams`(
    executable: String,
    code: String,
  ) throws {
    let directory = try Self.programs()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      executable,
      [],
      in: directory.url.path,
    ))

    #expect(outcome == CapsuleSpawnOutcome(
      exitStatus: nil,
      signal: nil,
      standardOutput: nil,
      standardError: nil,
      errorMessage: "spawnSync \(executable) \(code)",
    ))
  }

  @Test(arguments: [("missing", "ENOENT"), ("plain.sh", "ENOTDIR")])
  func `a working directory that is not one stops the start`(
    workingDirectory: String,
    code: String,
  ) throws {
    let directory = try Self.programs()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "exit 0"],
      in: directory.url.path + "/" + workingDirectory,
    ))

    #expect(outcome.exitStatus == nil)
    #expect(outcome.errorMessage == "spawnSync /bin/sh \(code)")
  }

  @Test
  func `the PATH search skips an entry it may not execute and finds a later one`() throws {
    let directory = try Self.programs()
    let root = directory.url.path

    let found = try CapsuleProcessSpawner().spawn(Self.request(
      "tool",
      [],
      in: root,
      environment: ["PATH=\(root)/denied:\(root)/allowed"],
    ))
    let denied = try CapsuleProcessSpawner().spawn(Self.request(
      "tool",
      [],
      in: root,
      environment: ["PATH=\(root)/denied:\(root)/nowhere"],
    ))

    #expect(found.standardOutput == "allowed\n")
    #expect(denied.errorMessage == "spawnSync tool EACCES")
  }

  @Test(arguments: [":", "allowed", "./allowed"])
  func `empty and relative PATH entries are read from the working directory`(
    entry: String,
  ) throws {
    let directory = try Self.programs()
    let root = directory.url.path
    let workingDirectory = entry == ":" ? root + "/allowed" : root

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "tool",
      [],
      in: workingDirectory,
      environment: ["PATH=\(entry == ":" ? ":/nowhere" : entry)"],
    ))

    #expect(outcome.standardOutput == "allowed\n")
  }

  @Test
  func `with no PATH the default search path is used`() throws {
    let directory = try TemporaryDirectory()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "ls",
      ["-d", "/"],
      in: directory.url.path,
      environment: [],
    ))

    #expect(outcome.exitStatus == 0)
    #expect(outcome.standardOutput == "/\n")
  }

  @Test
  func `the child sees exactly the environment given, in order, and an empty stdin`() throws {
    let directory = try TemporaryDirectory()
    let environment = ["B=1", "A=2", "PATH=/usr/bin"]

    let printed = try CapsuleProcessSpawner().spawn(Self.request(
      "/usr/bin/env",
      [],
      in: directory.url.path,
      environment: environment,
    ))
    let input = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "cat; echo end; [ -p /dev/stdin ] && echo fifo || echo not-fifo"],
      in: directory.url.path,
    ))

    #expect(printed.standardOutput == "B=1\nA=2\nPATH=/usr/bin\n")
    #expect(input.standardOutput == "end\nnot-fifo\n")
  }

  @Test(arguments: [
    ("KILL", "SIGKILL"),
    ("TERM", "SIGTERM"),
    ("SEGV", "SIGSEGV"),
    ("ABRT", "SIGABRT"),
    ("USR2", "SIGUSR2"),
    ("PIPE", "SIGPIPE"),
    ("ALRM", "SIGALRM"),
  ])
  func `a program ended by a signal reports the signal's name and no status`(
    signal: String,
    name: String,
  ) throws {
    let directory = try TemporaryDirectory()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "kill -\(signal) $$"],
      in: directory.url.path,
    ))

    #expect(outcome.exitStatus == nil)
    #expect(outcome.signal == name)
    #expect(outcome.standardOutput == "")
    #expect(outcome.errorMessage == nil)
  }

  @Test
  func `past the timeout the program gets SIGTERM and what it wrote is kept`() throws {
    let directory = try TemporaryDirectory()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "printf partial; exec sleep 5"],
      in: directory.url.path,
      timeoutMilliseconds: 200,
    ))

    #expect(outcome.exitStatus == nil)
    #expect(outcome.signal == "SIGTERM")
    #expect(outcome.standardOutput == "partial")
  }

  @Test
  func `a grandchild holding the pipes open does not outlive the timeout`() throws {
    let directory = try TemporaryDirectory()
    let started = ContinuousClock.now

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "sleep 3; true"],
      in: directory.url.path,
      timeoutMilliseconds: 200,
    ))

    #expect(outcome.signal == "SIGTERM")
    #expect(ContinuousClock.now - started < .seconds(2))
  }

  @Test
  func `output past one MiB across both streams ends the program with SIGTERM`() throws {
    let directory = try TemporaryDirectory()

    let overflow = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "printf short; exec /usr/bin/yes 1>&2"],
      in: directory.url.path,
    ))
    let exact = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "head -c 1048576 /dev/zero | tr '\\0' o"],
      in: directory.url.path,
    ))

    #expect(overflow.exitStatus == nil)
    #expect(overflow.signal == "SIGTERM")
    #expect(overflow.standardOutput == "short")
    let captured = (overflow.standardError ?? "").utf8.count + 5
    #expect(captured > 1_048_576)
    #expect(exact.exitStatus == 0)
    #expect(exact.standardOutput?.utf8.count == 1_048_576)
  }

  @Test
  func `invalid UTF-8 output is decoded with replacement characters`() throws {
    let directory = try TemporaryDirectory()

    let outcome = try CapsuleProcessSpawner().spawn(Self.request(
      "/bin/sh",
      ["-c", "printf '\\377a\\342\\202'"],
      in: directory.url.path,
    ))

    #expect(outcome.standardOutput == "\u{FFFD}a\u{FFFD}")
  }

  private static func request(
    _ executable: String,
    _ arguments: [String],
    in workingDirectory: String,
    environment: [String] = [path],
    timeoutMilliseconds: Double = 30000,
  ) -> CapsuleSpawnRequest {
    CapsuleSpawnRequest(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeoutMilliseconds: timeoutMilliseconds,
    )
  }

  /// A directory of programs that cannot start, and a `tool` that can.
  private static func programs() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory()
    let scripts: [(path: String, contents: String)] = [
      ("plain.sh", "#!/bin/sh\nexit 0\n"),
      ("no-shebang.sh", "exit 0\n"),
      ("bad-interpreter.sh", "#!/nonexistent/interpreter\n"),
      ("denied/tool", "#!/bin/sh\necho denied\n"),
      ("allowed/tool", "#!/bin/sh\necho allowed\n"),
    ]
    let executable: Set = ["no-shebang.sh", "bad-interpreter.sh", "allowed/tool"]
    for script in scripts {
      let url = try directory.writeFile(script.path, contents: script.contents)
      try #require(chmod(url.path, executable.contains(script.path) ? 0o755 : 0o644) == 0)
    }
    _ = try directory.makeDirectory("folder")
    return directory
  }
}
