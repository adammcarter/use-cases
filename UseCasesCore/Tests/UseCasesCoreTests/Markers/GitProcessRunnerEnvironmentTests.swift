import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// git run in a given environment, its stderr collected in order rather than
/// written straight to this process's.
struct GitProcessRunnerEnvironmentTests {
  @Test
  func `collects git's stderr into the log it is given`() throws {
    let directory = try TemporaryDirectory()
    let log = ProcessStandardErrorLog()
    let runner = GitProcessRunner(
      environment: ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"],
      standardErrorLog: log,
    )

    #expect(throws: GitError.self) {
      try runner.run(["show", "HEAD:missing"], workingDirectory: directory.url.path)
    }
    #expect(log.text.hasPrefix("fatal: not a git repository"))
  }

  @Test
  func `runs git with exactly the environment it is given`() throws {
    let directory = try TemporaryDirectory()
    let runner = GitProcessRunner(environment: [
      "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
      "GIT_CONFIG_GLOBAL": "/dev/null",
      "GIT_CONFIG_NOSYSTEM": "1",
      "GIT_CONFIG_COUNT": "1",
      "GIT_CONFIG_KEY_0": "probe.value",
      "GIT_CONFIG_VALUE_0": "from-environment",
    ])

    let output = try runner.run(
      ["config", "--get", "probe.value"],
      workingDirectory: directory.url.path,
    )

    #expect(output == "from-environment\n")
  }

  @Test
  func `keeps chunks in the order they were appended`() {
    let log = ProcessStandardErrorLog()

    log.append("one\n")
    log.append(Data("two\n".utf8))

    #expect(log.text == "one\ntwo\n")
  }
}
