import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct InitCommandHooksTests {
  private static let program = "/opt/use-cases/bin/use-cases"

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
  }

  private func run(
    _ arguments: [String],
    clone: HookPlanner? = nil,
  ) async -> CommandResult {
    await place.run(
      arguments,
      hooks: clone ?? place.clone(),
      program: Self.program,
    )
  }

  private func hook(_ event: String) -> URL {
    place.url.appendingPathComponent(".git/hooks/\(event)")
  }

  private var outsideGit: HookPlanner {
    HookPlanner(git: MockGitInspector(failing: .notAGitRepository(folder: place.realPath)))
  }

  // MARK: - Only when asked

  @Test
  func `hooks are added only when the flag asks, and it asks nothing`() async throws {
    let plain = await run(["--json", "init", "--no-input"])

    #expect(try plain.document()["hooks"] == .array([]))
    #expect(!FileManager.default.fileExists(atPath: hook("pre-commit").path))
  }

  @Test(arguments: [
    ("commit", ["commit"]),
    ("push", ["push"]),
    ("commit,push", ["commit", "push"]),
    ("push,commit", ["commit", "push"]),
    ("push,push", ["push"]),
  ])
  func `the hooks the flag names are added, in the fixed order`(
    flag: String,
    added: [String],
  ) async throws {
    let result = await run(["--json", "init", "--no-input", "--hooks", flag])

    #expect(result.exitCode == 0)
    #expect(try result.document()["hooks"]?.strings == added)

    for name in added {
      let event = name == "commit" ? "pre-commit" : "pre-push"

      #expect(FileManager.default.isExecutableFile(atPath: hook(event).path))
      #expect(try String(contentsOf: hook(event), encoding: .utf8).contains(Self.program))
    }
  }

  @Test
  func `the people see a line for each hook added, after gitignore`() async {
    let result = await run(["init", "--no-input", "--minimal", "--hooks", "commit,push"])

    #expect(result.exitCode == 0)
    #expect(
      result.outputLines == [
        "created  use-cases.yml",
        "added    .use-cases/ to .gitignore",
        "added    the commit hook (use-cases validate)",
        "added    the push hook (use-cases status --gate)",
        "→ use-cases status",
      ],
    )
  }

  @Test
  func `the hook names the workspace from the top of the work tree`() async throws {
    try place.folder.write("services/pay/keep.txt", "x")

    let result = await run(
      ["--json", "--workspace", "services/pay", "init", "--minimal", "--hooks", "commit"],
    )

    #expect(result.exitCode == 0)
    #expect(
      try String(contentsOf: hook("pre-commit"), encoding: .utf8)
        .contains("exec use-cases --workspace \"services/pay\" validate --quiet"),
    )
  }

  @Test
  func `an existing workspace gains the hooks too`() async throws {
    _ = await place.run(["init", "--minimal"])

    let result = await run(["--json", "init", "--hooks", "push"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["hooks"]?.strings == ["push"])
    #expect(FileManager.default.fileExists(atPath: hook("pre-push").path))
  }

  // MARK: - Left alone, or no clone

  @Test
  func `outside git the files are still written, the exit is 1 and the last note says why`()
    async throws
  {
    let result = await run(
      ["--json", "init", "--hooks", "commit"],
      clone: outsideGit,
    )
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(document["hooks"] == .array([]))
    #expect(document["notes"]?.strings.last?.contains("not a git repository") == true)
    #expect(try place.snapshot().keys.contains("use-cases.yml"))
  }

  @Test
  func `another hook is left alone, the files are written and the exit is 1`() async throws {
    try place.folder.write(".git/hooks/pre-commit", "#!/bin/sh\necho mine\n")

    let result = await run(["--json", "init", "--hooks", "commit,push"])
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(document["hooks"]?.strings == ["push"])
    #expect(document["notes"]?.strings.last?.contains("validate --quiet") == true)
    #expect(try String(contentsOf: hook("pre-commit"), encoding: .utf8) == "#!/bin/sh\necho mine\n")
    #expect(FileManager.default.fileExists(atPath: hook("pre-push").path))
    #expect(try place.snapshot().keys.contains("use-cases.yml"))
  }

  @Test
  func `a hook manager is never written into and the exit is 1`() async throws {
    let result = await run(
      ["--json", "init", "--hooks", "commit"],
      clone: place.clone(isManaged: true),
    )

    #expect(result.exitCode == 1)
    #expect(try result.document()["hooks"] == .array([]))
    #expect(try result.document()["notes"]?.strings.last?.contains("core.hooksPath") == true)
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent(".git/hooks").path))
  }

  @Test
  func `outside git the people see the note and the exit is 1`() async {
    let result = await run(
      ["init", "--no-input", "--minimal", "--hooks", "commit"],
      clone: outsideGit,
    )

    #expect(result.exitCode == 1)
    #expect(result.outputLines.contains("note: not a git repository, so no hooks were added"))
  }

  // MARK: - Dry run

  @Test
  func `a dry run says would of the hooks and writes nothing`() async throws {
    let before = try place.snapshot()

    let result = await run(["init", "--no-input", "--minimal", "--hooks", "push", "--dry-run"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.last == "would add     the push hook (use-cases status --gate)")
    #expect(try place.snapshot() == before)
  }

  @Test
  func `the document of a dry run is the one of the real run`() async throws {
    let arguments = ["init", "--no-input", "--minimal", "--hooks", "commit"]

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
    #expect(real["hooks"]?.strings == ["commit"])
  }

  @Test
  func `the document follows the published schema, hooks and all`() async throws {
    let result = await run(["--json", "init", "--minimal", "--hooks", "commit,push"])
    let schema = try PublishedSchema(path: "schemas/output/cli-init.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  // MARK: - Cancellation

  @Test
  func `a request cancelled before the write writes no file and no hook`() async throws {
    let result = await place.run(
      ["--json", "init", "--minimal", "--hooks", "commit"],
      hooks: place.clone(),
      cancellation: ObservedCancellationScope(
        makeObserver: {
          MockCancellation.always
        },
      ),
    )

    #expect(result.exitCode == 130)
    #expect(try place.snapshot().keys.sorted() == [".git/HEAD"])
  }

  @Test
  func `the files and the hooks are written under one claim to write`() async {
    let log = place.scratch.url.appendingPathComponent("log")

    _ = await place.run(
      ["init", "--no-input", "--minimal", "--hooks", "commit"],
      hooks: place.clone(),
      writer: SpyPlanWriting(log: log),
    )

    #expect(SpyPlanWriting(log: log).applied.count == 2)
    #expect(SpyPlanWriting(log: log).applied.last == place.realPath + "/.git")
  }
}
