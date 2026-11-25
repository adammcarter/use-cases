import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct HooksCommandTests {
  private static let program = "/opt/use-cases/bin/use-cases"

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
  }

  private func run(
    _ arguments: [String],
    from directory: URL? = nil,
    clone: HookPlanner? = nil,
  ) async -> CommandResult {
    await place.run(
      arguments,
      from: directory,
      hooks: clone ?? place.clone(),
      program: Self.program,
    )
  }

  private func hook(_ event: String) -> URL {
    place.url.appendingPathComponent(".git/hooks/\(event)")
  }

  private func states(_ result: CommandResult) throws -> [String] {
    guard case let .array(hooks)? = try result.document()["hooks"] else {
      return []
    }

    return hooks.compactMap { hook in
      guard case let .string(state)? = hook["state"] else {
        return nil
      }

      return state
    }
  }

  // MARK: - Listing

  // @use-case:hooks.opt-in#swift-tests.list
  @Test
  func `listing says what each hook is and runs, and offers to add the missing ones`() async {
    let result = await run(["hooks"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      result.outputLines == [
        "commit   not installed  use-cases validate",
        "push     not installed  use-cases status --gate",
        "→ use-cases hooks add commit push",
      ],
    )
  }

  // @use-case:end hooks.opt-in#swift-tests.list

  // @use-case:hooks.opt-in#swift-tests.list
  @Test
  func `listing writes nothing`() async throws {
    let before = try place.snapshot()

    _ = await run(["hooks"])

    #expect(try place.snapshot() == before)
  }

  // @use-case:end hooks.opt-in#swift-tests.list

  @Test
  func `the hint offers only the hooks that are not installed, and quiet leaves it out`() async {
    _ = await run(["hooks", "add", "commit"])

    let result = await run(["hooks"])
    let quiet = await run(["hooks", "--quiet"])

    #expect(result.outputLines.first == "commit   installed      use-cases validate")
    #expect(result.outputLines.last == "→ use-cases hooks add push")
    #expect(quiet.outputLines.last?.hasPrefix("→") == false)
  }

  @Test
  func `with every hook installed there is nothing to suggest`() async {
    _ = await run(["hooks", "add", "commit", "push"])

    let result = await run(["hooks"])

    #expect(result.outputLines.count == 2)
    #expect(result.exitCode == 0)
  }

  // MARK: - Adding and removing

  @Test
  func `adding writes a runnable script that remembers the program, and tells what it did`()
    async throws
  {
    let result = await run(["hooks", "add", "commit"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "added the commit hook")
    #expect(try String(contentsOf: hook("pre-commit"), encoding: .utf8).contains(Self.program))
    #expect(FileManager.default.isExecutableFile(atPath: hook("pre-commit").path))
    #expect(!FileManager.default.fileExists(atPath: hook("pre-push").path))
  }

  @Test
  func `both hooks are added in the fixed order and listed installed`() async throws {
    let result = await run(["--json", "hooks", "add", "push", "commit"])
    let document = try result.document()

    #expect(document["changed"]?.strings == ["commit", "push"])
    #expect(try states(result) == ["installed", "installed"])
    #expect(document["dry_run"] == .boolean(false))
  }

  @Test
  func `adding what is installed changes nothing`() async throws {
    _ = await run(["hooks", "add", "commit"])
    let before = try Data(contentsOf: hook("pre-commit"))

    let result = await run(["--json", "hooks", "add", "commit"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["changed"] == .array([]))
    #expect(try Data(contentsOf: hook("pre-commit")) == before)
  }

  @Test
  func `removing takes out only a hook that is ours`() async {
    _ = await run(["hooks", "add", "commit", "push"])

    let result = await run(["hooks", "remove", "commit"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "removed the commit hook")
    #expect(!FileManager.default.fileExists(atPath: hook("pre-commit").path))
    #expect(FileManager.default.fileExists(atPath: hook("pre-push").path))
  }

  @Test
  func `removing what is not there changes nothing and is done`() async throws {
    let result = await run(["--json", "hooks", "remove", "push"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["changed"] == .array([]))
  }

  // MARK: - Never overwrites

  // @use-case:hooks.never-overwrites#swift-tests.other-hook
  @Test
  func `another hook is left alone, the line to add is given, and the exit is 1`() async throws {
    try place.folder.write(".git/hooks/pre-commit", "#!/bin/sh\necho mine\n")

    let result = await run(["--json", "hooks", "add", "commit"])
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(result.standardError.isEmpty)
    #expect(document["changed"] == .array([]))
    #expect(document["notes"]?.strings.first?
      .contains("use-cases --workspace \".\" validate --quiet") == true)
    #expect(try String(contentsOf: hook("pre-commit"), encoding: .utf8) == "#!/bin/sh\necho mine\n")
  }

  // @use-case:end hooks.never-overwrites#swift-tests.other-hook

  @Test
  func `removing another hook is left alone with exit 1`() async throws {
    try place.folder.write(".git/hooks/pre-commit", "#!/bin/sh\necho mine\n")

    let result = await run(["--json", "hooks", "remove", "commit"])

    #expect(result.exitCode == 1)
    #expect(try result.document()["changed"] == .array([]))
    #expect(FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test
  func `a hook manager is never written into, and the line for it is given with exit 1`()
    async throws
  {
    let result = await run(
      ["--json", "hooks", "add", "push"],
      clone: place.clone(isManaged: true),
    )
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(document["managed"] == .boolean(true))
    #expect(document["changed"] == .array([]))
    #expect(document["notes"]?.strings.first?.contains("core.hooksPath") == true)
    #expect(try states(result) == ["managed", "managed"])
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent(".git/hooks").path))
  }

  @Test
  func `listing under a hook manager or beside another hook is not something that needs you`()
    async throws
  {
    try place.folder.write(".git/hooks/pre-push", "#!/bin/sh\n")

    #expect(await run(["hooks"]).exitCode == 0)
    #expect(await run(["hooks"], clone: place.clone(isManaged: true)).exitCode == 0)
  }

  // MARK: - Dry run

  @Test
  func `a dry run writes nothing and says would`() async throws {
    let before = try place.snapshot()

    let result = await run(["hooks", "add", "commit", "--dry-run"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "would add the commit hook")
    #expect(try place.snapshot() == before)
  }

  @Test
  func `a dry run of a remove leaves the hook`() async throws {
    _ = await run(["hooks", "add", "commit"])

    let result = await run(["--json", "hooks", "remove", "commit", "--dry-run"])

    #expect(try result.document()["changed"]?.strings == ["commit"])
    #expect(FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test(arguments: [
    ["hooks", "add", "commit", "push"],
    ["hooks", "add", "push"],
  ])
  func `the document of a dry run is the one of the real run`(arguments: [String]) async throws {
    guard case var .object(dry) = try await run(["--json"] + arguments + ["--dry-run"]).document(),
          case var .object(real) = try await run(["--json"] + arguments).document()
    else {
      Issue.record("not documents")
      return
    }

    #expect(dry["dry_run"] == .boolean(true))
    #expect(real["dry_run"] == .boolean(false))

    dry["dry_run"] = nil
    real["dry_run"] = nil

    #expect(dry == real)
  }

  // MARK: - Where it works

  @Test
  func `it needs the workspace root and never the model`() async throws {
    try place.folder.write("use-cases/bad.yml", "use_cases:\n  - id: bad\n    surprise: true\n")

    let result = await run(["hooks", "add", "commit"])

    #expect(result.exitCode == 0)
    #expect(FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test
  func `a workspace in a subfolder is found from below and named from the top`() async throws {
    try FileManager.default.removeItem(at: place.url.appendingPathComponent("use-cases.yml"))
    try place.folder.write("services/pay/use-cases.yml", "schema_version: 1\nroot: true\n")
    let below = place.url.appendingPathComponent("services/pay")

    let result = await run(
      ["--json", "hooks", "add", "commit"],
      from: below,
    )

    #expect(result.exitCode == 0)
    #expect(try result.document()["hooks_dir"] == .string("../../.git/hooks"))
  }

  @Test
  func `no workspace is a refusal, and nothing is written`() async throws {
    try FileManager.default.removeItem(at: place.url.appendingPathComponent("use-cases.yml"))

    let result = await run(["--json", "hooks", "add", "commit"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent(".git/hooks").path))
  }

  // MARK: - Refusals

  @Test
  func `outside git it is a refusal that says so`() async throws {
    let result = await run(
      ["--json", "hooks", "add", "commit"],
      clone: HookPlanner(
        git: MockGitInspector(failing: .notAGitRepository(folder: place.realPath)),
      ),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("not a git repository"))
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
  }

  @Test
  func `git that cannot be run is a refusal that says so, never a missing repository`()
    async
  {
    let result = await run(
      ["hooks"],
      clone: HookPlanner(git: MockGitInspector(failing: .gitUnavailable(reason: "not found"))),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("git cannot be run"))
    #expect(!result.standardError.contains("not a git repository"))
  }

  @Test
  func `an unknown hook is a usage error that names it`() async throws {
    let result = await run(["--json", "hooks", "add", "merge"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("unknown hook merge"))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent(".git/hooks").path))
  }

  @Test(arguments: [
    ["hooks", "add"],
    ["hooks", "remove"],
    ["hooks", "install", "commit"],
    ["hooks", "commit"],
  ])
  func `an action with no hooks, or an action that is not one, is a usage error`(
    arguments: [String],
  ) async {
    let result = await run(arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.hasPrefix("error: "))
  }

  @Test
  func `a refusal comes before the workspace is looked for`() async throws {
    try FileManager.default.removeItem(at: place.url.appendingPathComponent("use-cases.yml"))

    let result = await run(["hooks", "add", "merge"])

    #expect(result.standardError.contains("unknown hook merge"))
  }

  // MARK: - Cancellation

  @Test
  func `a request cancelled before the write writes nothing`() async {
    let result = await place.run(
      ["--json", "hooks", "add", "commit"],
      hooks: place.clone(),
      cancellation: ObservedCancellationScope(
        makeObserver: {
          MockCancellation.always
        },
      ),
    )

    #expect(result.exitCode == 130)
    #expect(!FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test
  func `the hooks are written to the folder above the hooks folder`() async {
    let log = place.scratch.url.appendingPathComponent("log")

    _ = await place.run(
      ["hooks", "add", "commit"],
      hooks: place.clone(),
      writer: SpyPlanWriting(log: log),
    )

    #expect(SpyPlanWriting(log: log).applied == [place.realPath + "/.git"])
  }
}

// MARK: - What a dry run says

extension HooksCommandTests {
  @Test
  func `a dry run says a hook would be installed, never that it is`() async {
    let result = await run(["hooks", "add", "commit", "push", "--dry-run"])

    #expect(result.outputLines == [
      "would add the commit hook",
      "would add the push hook",
      "commit   would install  use-cases validate",
      "push     would install  use-cases status --gate",
    ])
  }

  @Test
  func `a dry run of a remove says the hook would be removed, and leaves it`() async {
    _ = await run(["hooks", "add", "commit"])

    let result = await run(["hooks", "remove", "commit", "--dry-run"])

    #expect(result.outputLines.contains("commit   would remove   use-cases validate"))
    #expect(FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }
}
