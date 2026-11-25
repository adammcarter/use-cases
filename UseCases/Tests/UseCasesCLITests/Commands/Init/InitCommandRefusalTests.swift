import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct InitCommandRefusalTests {
  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  // MARK: - Refusals

  @Test
  func `a folder inside a workspace is refused as refused, naming the root, and nothing is made`()
    async throws
  {
    _ = await place.run(["init", "--minimal"])
    try place.folder.write("services/pay/keep.txt", "x")
    let before = try place.snapshot()

    let result = await place.run(
      ["--json", "--workspace", "services/pay", "init"],
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("inside the workspace"))
    #expect(result.standardError.contains(place.realPath))
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(try place.snapshot() == before)
  }

  @Test
  func `a child scope's file is not a workspace root and is left alone`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nprefix: svc\n")

    let result = await place.run(["init", "--no-input"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("not a workspace root"))
    #expect(try place.snapshot() == ["use-cases.yml": "schema_version: 1\nprefix: svc\n"])
  }

  @Test(arguments: ["Shop", "shop_", "shop..app", "-shop"])
  func `a prefix off the grammar is a usage error and writes nothing`(prefix: String) async throws {
    let result = await place.run(["--json", "init", "--prefix=\(prefix)"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("not a valid prefix"))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(try place.snapshot().isEmpty)
  }

  @Test
  func `a different prefix is refused and never dropped`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\nprefix: shop\n")

    let result = await place.run(["--json", "init", "--prefix", "other"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(try place.read("use-cases.yml") == "schema_version: 1\nroot: true\nprefix: shop\n")
    #expect(!FileManager.default.fileExists(
      atPath: place.url.appendingPathComponent("use-cases-bridge.yml").path,
    ))
  }

  @Test
  func `an INVALID workspace is refused as invalid and nothing is added to it`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-cases/bad.yml", "use_cases:\n  - id: bad\n    surprise: true\n")
    let before = try place.snapshot()

    let result = await place.run(["--json", "init"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(result.standardError.contains("use-cases/bad.yml"))
    #expect(try place.snapshot() == before)
  }

  @Test
  func `an INVALID kept file is refused, because the workspace would be invalid after it`()
    async throws
  {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("use-case-groups.yml", InitFolder.unknownIdGroups)
    let before = try place.snapshot()

    let result = await place.run(["init", "--no-input"])

    #expect(result.exitCode == 2)
    #expect(try place.snapshot() == before)
  }

  @Test
  func `a link problem in an existing workspace refuses init, as it refuses every command`()
    async throws
  {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write("src/a.swift", "// \(MarkerText.sentinel)app.nothing#x\nwork()\n")
    let before = try place.snapshot()

    let result = await place.run(["init", "--no-input"])

    #expect(result.exitCode == 2)
    #expect(try place.snapshot() == before)
  }

  // MARK: - Hooks and questions

  @Test
  func `a refusal comes before hooks are planned`() async throws {
    let result = await place.run(["init", "--prefix", "Shop", "--hooks", "commit"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("not a valid prefix"))
    #expect(try place.snapshot().isEmpty)
  }

  @Test(arguments: ["pre-commit", "commit,", "commit push", "", "merge", "Commit"])
  func `a name that is not a hook is a usage error in a repository or out of one`(
    hooks: String,
  ) async throws {
    let outside = await place.run(["--json", "init", "--hooks", hooks])
    let inside = await place.run(
      ["--json", "init", "--hooks", hooks],
      hooks: place.clone(),
    )

    for result in [outside, inside] {
      #expect(result.exitCode == 2)
      #expect(try result.document()["error"]?["kind"] == .string("usage"))
      #expect(result.standardError.contains("commit, push or commit,push"))
    }

    #expect(try place.snapshot().isEmpty)
  }

  @Test
  func `git that cannot be run is a refusal that says so, and nothing is written`() async throws {
    let result = await place.run(
      ["--json", "init", "--hooks", "commit"],
      hooks: HookPlanner(git: MockGitInspector(failing: .gitUnavailable(reason: "no such file"))),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("git cannot be run"))
    #expect(!result.standardError.contains("not a git repository"))
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(try place.snapshot().isEmpty)
  }

  @Test(arguments: [["init", "--no-input"], ["--json", "init"]])
  func `at a terminal no-input and json never ask`(arguments: [String]) async {
    let prompter = MockPrompter()

    let result = await place.run(
      arguments,
      isTerminal: true,
      prompter: prompter,
    )

    #expect(result.exitCode == 0)
    #expect(await prompter.transcript.isEmpty)
  }
}
