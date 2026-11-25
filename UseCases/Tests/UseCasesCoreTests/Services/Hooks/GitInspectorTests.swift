import Foundation
import Testing
@testable import UseCasesCore

struct GitInspectorTests {
  private static let top = ["rev-parse", "--show-toplevel"]
  private static let hooks = ["rev-parse", "--git-path", "hooks"]
  private static let configured = ["config", "--get", "core.hooksPath"]

  private let folder: TemporaryDirectory

  init() throws {
    folder = try TemporaryDirectory()
  }

  private func inspector(
    _ answers: [[String]: Result<ProcessRun, ProcessSupervisingError>],
  ) -> (GitInspector, ScriptedProcessSupervisor) {
    let supervisor = ScriptedProcessSupervisor(answers: answers)

    return (
      GitInspector(
        supervisor: supervisor,
        fileSystem: LocalFileSystem(),
      ),
      supervisor,
    )
  }

  private func clone(
    top: String? = nil,
    hooks: String = ".git/hooks",
    configured: Result<ProcessRun, ProcessSupervisingError> = ScriptedProcessSupervisor
      .exited(1),
  ) -> [[String]: Result<ProcessRun, ProcessSupervisingError>] {
    [
      Self.top: ScriptedProcessSupervisor.exited(0, (top ?? folder.url.path) + "\n"),
      Self.hooks: ScriptedProcessSupervisor.exited(0, hooks + "\n"),
      Self.configured: configured,
    ]
  }

  @Test
  func `it names the work tree and the hooks folder git gives, from where git was asked`()
    async throws
  {
    let (git, _) = inspector(clone())

    let location = try await git.locate(from: folder.url)

    #expect(location.workTree == folder.url)
    #expect(location.hooksFolder == folder.url.appendingPathComponent(".git/hooks"))
    #expect(!location.isManaged)
  }

  @Test
  func `it asks git three questions in the folder, each with a time to answer`() async throws {
    let (git, supervisor) = inspector(clone())

    _ = try await git.locate(from: folder.url)

    let requests = await supervisor.requests

    #expect(requests.map(\.arguments) == [
      ["git"] + Self.top, ["git"] + Self.hooks, ["git"] + Self.configured,
    ])
    #expect(requests.map(\.workingDirectory) == Array(repeating: folder.url, count: 3))
    #expect(requests.map(\.reportPath) == [nil, nil, nil])
    #expect(requests.map(\.timeout) == Array(repeating: .seconds(30), count: 3))
  }

  @Test
  func `a hooks folder git gives relative to the folder it was asked in is resolved from there`()
    async throws
  {
    // From a folder below the top, git says `../.git/hooks`: it is relative to where git ran,
    // not to the top of the work tree.
    try folder.write("services/pay/keep")
    try folder.makeDirectory(".git/hooks")
    let below = folder.location(of: "services/pay")
    let (git, _) = inspector(clone(hooks: "../../.git/hooks"))

    let location = try await git.locate(from: below)

    #expect(location.hooksFolder == folder.location(of: ".git/hooks"))
    #expect(location.workTree == folder.url)
  }

  @Test
  func `a hooks folder git gives in full is kept, and a link in it is resolved`() async throws {
    try folder.write("real/keep")
    try FileManager.default.createSymbolicLink(
      at: folder.location(of: "link"),
      withDestinationURL: folder.location(of: "real"),
    )
    let (git, _) = inspector(
      clone(hooks: folder.location(of: "link/modules/x/hooks").path),
    )

    let location = try await git.locate(from: folder.url)

    // The folder is not there: it is spelled from the nearest folder that is.
    #expect(location.hooksFolder == folder.url.appendingPathComponent("real/modules/x/hooks"))
  }

  @Test
  func `a warning git prints before its answer does not become the answer`() async throws {
    var answers = clone()
    answers[Self.top] = ScriptedProcessSupervisor.exited(
      0,
      "warning: unable to access '/x/attributes': Permission denied\n\(folder.url.path)\n",
    )
    let (git, _) = inspector(answers)

    #expect(try await git.locate(from: folder.url).workTree == folder.url)
  }

  @Test(arguments: [0, 1])
  func `core hooks path set is a hook manager and unset is not`(code: Int32) async throws {
    let (git, _) = inspector(
      clone(configured: ScriptedProcessSupervisor.exited(code, ".husky\n")),
    )

    #expect(try await git.locate(from: folder.url).isManaged == (code == 0))
  }

  @Test
  func `a folder git refuses is not in a git repository`() async {
    var answers = clone()
    answers[Self.top] = ScriptedProcessSupervisor.exited(
      128,
      "fatal: not a git repository (or any of the parent directories): .git\n",
    )
    let (git, _) = inspector(answers)

    await #expect(throws: HooksError.notAGitRepository(folder: folder.url.path)) {
      try await git.locate(from: folder.url)
    }
  }

  @Test
  func `git that cannot be started is said so and is not a missing repository`() async {
    let (git, _) = inspector(
      [Self.top: .failure(.couldNotLaunch(reason: "No such file or directory"))],
    )

    await #expect(throws: HooksError.gitUnavailable(reason: "No such file or directory")) {
      try await git.locate(from: folder.url)
    }
  }

  @Test(arguments: [
    ProcessTermination.signaled(9), .timedOut(after: .seconds(30)), .cancelled,
  ])
  func `git that does not finish is unavailable`(termination: ProcessTermination) async {
    let run = ProcessRun(
      termination: termination,
      console: .empty,
      wasLaunched: true,
    )
    let (git, _) = inspector([Self.top: .success(run)])

    await #expect(throws: HooksError.gitUnavailable(reason: "git did not finish answering")) {
      try await git.locate(from: folder.url)
    }
  }

  @Test
  func `a hooks folder git cannot name is unavailable`() async {
    var answers = clone()
    answers[Self.hooks] = ScriptedProcessSupervisor.exited(129, "usage\n")
    let (git, _) = inspector(answers)

    await #expect(throws: HooksError.self) {
      try await git.locate(from: folder.url)
    }
  }

  @Test
  func `a configuration git cannot read is unavailable, not unset`() async {
    let (git, _) = inspector(clone(configured: ScriptedProcessSupervisor.exited(128, "bad\n")))

    await #expect(throws: HooksError.gitUnavailable(reason: "it could not read core.hooksPath")) {
      try await git.locate(from: folder.url)
    }
  }
}
