import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The real verifier runner against real child processes, each expectation
/// what node's `spawnSync` was measured doing for the same child on this
/// machine. Every child is a `/bin/sh` one-liner; nothing waits seconds.
struct VerifyProcessRunnerTests {
  static let outOfRange =
    #"The value of "timeout" is out of range. It must be >= 0 && <= 9007199254740991. Received "#

  private let runner = VerifyProcessRunner()

  private func shell(
    _ script: String,
    workingDirectory: String = "/",
    timeoutSeconds: Double? = nil,
  ) throws -> VerifySpawnResult {
    try runner.run(VerifySpawnRequest(
      command: ["/bin/sh", "-c", script],
      workingDirectory: workingDirectory,
      timeoutSeconds: timeoutSeconds,
    ))
  }

  @Test(arguments: [0, 1, 7, 124, 255])
  func `a child's exit status is its exit code`(status: Int) throws {
    let result = try shell("exit \(status)")
    #expect(result == VerifySpawnResult(
      exitCode: status,
      timedOut: false,
      standardOutput: "",
      standardError: "",
    ))
  }

  @Test
  func `stdout and stderr are captured apart`() throws {
    let result = try shell("printf 'out\\n'; printf 'err' >&2; printf 'more'")
    #expect(result.standardOutput == "out\nmore")
    #expect(result.standardError == "err")
  }

  @Test
  func `stdin reads as empty`() throws {
    #expect(try shell("wc -c | tr -d ' '").standardOutput == "0\n")
  }

  @Test(arguments: [
    ["no-such-verifier-command-3d4c"],
    ["/no/such/verifier"],
    ["/tmp"],
    ["/etc/hosts"],
  ])
  func `a program that cannot start exits 1 with no output`(command: [String]) throws {
    let result = try runner.run(VerifySpawnRequest(
      command: command,
      workingDirectory: "/",
      timeoutSeconds: nil,
    ))
    #expect(result == VerifySpawnResult(
      exitCode: 1,
      timedOut: false,
      standardOutput: "",
      standardError: "",
    ))
  }

  @Test
  func `a working directory that does not exist exits 1`() throws {
    let result = try shell("echo ran", workingDirectory: "/no/such/directory/3d4c")
    #expect(result == VerifySpawnResult(
      exitCode: 1,
      timedOut: false,
      standardOutput: "",
      standardError: "",
    ))
  }

  @Test
  func `a bare name is found on PATH and runs in the working directory with the environment`(
  ) throws {
    let directory = try TemporaryDirectory()
    let root = try NodeFile.realPath(directory.url.path)
    let result = try runner.run(VerifySpawnRequest(
      command: ["sh", "-c", "pwd -P; printf '%s' \"$HOME\""],
      workingDirectory: root,
      timeoutSeconds: nil,
    ))
    #expect(result.exitCode == 0)
    #expect(result
      .standardOutput == root + "\n" + (ProcessInfo.processInfo.environment["HOME"] ?? ""))
  }

  @Test
  func `a relative path is resolved against the working directory`() throws {
    let directory = try TemporaryDirectory()
    let root = try NodeFile.realPath(directory.url.path)
    try NodeFile.makeDirectories(atPath: root + "/bin")
    try NodeFile.writeText("#!/bin/sh\necho relative-ok\n", atPath: root + "/bin/tool")
    try #require(chmod(root + "/bin/tool", 0o755) == 0)
    let result = try runner.run(VerifySpawnRequest(
      command: ["./bin/tool"],
      workingDirectory: root,
      timeoutSeconds: nil,
    ))
    #expect(result.standardOutput == "relative-ok\n")
  }

  @Test
  func `invalid UTF-8 is decoded with each maximal invalid subpart replaced`() throws {
    // node measured: a FFFD b FFFD c FFFD FFFD FFFD d FFFD FFFD e FFFD
    let result = try shell(#"printf 'a\377b\342\202c\355\240\200d\300\257e\360\237\230'"#)
    #expect(result
      .standardOutput == "a\u{FFFD}b\u{FFFD}c\u{FFFD}\u{FFFD}\u{FFFD}d\u{FFFD}\u{FFFD}e\u{FFFD}")
  }

  @Test
  func `past the timeout the child is terminated, later output is dropped, and it is 124`(
  ) throws {
    let started = ContinuousClock.now
    let result = try shell("echo before; exec sleep 5", timeoutSeconds: 0.25)
    #expect(result == VerifySpawnResult(
      exitCode: 124,
      timedOut: true,
      standardOutput: "before\n",
      standardError: "",
    ))
    #expect(ContinuousClock.now - started < .seconds(3))
  }

  @Test
  func `a child that exits itself on the timeout signal keeps its status yet is timed out`(
  ) throws {
    let result = try shell("trap 'exit 0' TERM; echo pre; sleep 5 & wait", timeoutSeconds: 0.25)
    #expect(result == VerifySpawnResult(
      exitCode: 0,
      timedOut: true,
      standardOutput: "pre\n",
      standardError: "",
    ))
  }

  @Test
  func `a timeout of zero is no timeout`() throws {
    let result = try shell("sleep 0.3; echo done", timeoutSeconds: 0)
    #expect(result == VerifySpawnResult(
      exitCode: 0,
      timedOut: false,
      standardOutput: "done\n",
      standardError: "",
    ))
  }

  @Test
  func `a child killed by a signal other than the timeout's exits 1`() throws {
    let result = try shell("kill -9 $$")
    #expect(result == VerifySpawnResult(
      exitCode: 1,
      timedOut: false,
      standardOutput: "",
      standardError: "",
    ))
  }

  @Test
  func `output over a mebibyte across both streams terminates the child and exits 1`(
  ) throws {
    let result = try shell(
      "head -c 716800 /dev/zero; head -c 716800 /dev/zero >&2; exec sleep 5",
      timeoutSeconds: 10,
    )
    #expect(result.exitCode == 1)
    #expect(!result.timedOut)
    #expect(result.standardOutput.utf8.count + result.standardError.utf8.count > 1024 * 1024)
  }

  @Test
  func `output just under the cap on both streams is read in full without blocking either pipe`(
  ) throws {
    let result = try shell("head -c 600000 /dev/zero >&2; head -c 400000 /dev/zero; exit 3")
    #expect(result.exitCode == 3)
    #expect(result.standardError.utf8.count == 600_000)
    #expect(result.standardOutput.utf8.count == 400_000)
  }

  @Test
  func `a grandchild holding stdout open keeps the run open until it closes`() throws {
    let result = try shell("(sleep 0.3; echo late) & echo early")
    #expect(result == VerifySpawnResult(
      exitCode: 0,
      timedOut: false,
      standardOutput: "early\nlate\n",
      standardError: "",
    ))
  }

  @Test(arguments: [
    (
      [],
      Double?.none,
      "spawn_command_missing",
      #"The "file" argument must be of type string. Received undefined"#
    ),
    ([""], nil, "spawn_command_empty", "The argument 'file' cannot be empty. Received ''"),
    (
      ["/bin/ec\u{0}ho"],
      nil,
      "spawn_argument_null_byte",
      #"The argument 'file' must be a string without null bytes. Received '/bin/ec\x00ho'"#
    ),
    (
      ["/bin/echo", "ok", "a\u{0}b"],
      nil,
      "spawn_argument_null_byte",
      #"The argument 'args[1]' must be a string without null bytes. Received 'a\x00b'"#
    ),
    (
      ["/bin/echo"],
      0.0625,
      "spawn_timeout_not_integer",
      #"The value of "timeout" is out of range. It must be an integer. Received 62.5"#
    ),
    (
      ["/bin/echo"],
      -1,
      "spawn_timeout_out_of_range",
      VerifyProcessRunnerTests.outOfRange + "-1000"
    ),
    (
      ["/bin/echo"],
      9_007_199_254_741,
      "spawn_timeout_out_of_range",
      VerifyProcessRunnerTests.outOfRange + "9_007_199_254_741_000"
    ),
  ])
  func `a request node refuses throws node's refusal and starts nothing`(
    command: [String],
    timeoutSeconds: Double?,
    code: String,
    message: String,
  ) {
    let refusal = #expect(throws: VerifySpawnError.self) {
      try runner.run(VerifySpawnRequest(
        command: command,
        workingDirectory: "/",
        timeoutSeconds: timeoutSeconds,
      ))
    }
    #expect(refusal?.code == code)
    #expect(refusal?.message == message)
  }
}
