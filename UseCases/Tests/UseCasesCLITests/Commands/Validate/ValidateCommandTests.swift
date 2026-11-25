import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ValidateCommandTests {
  private static let root = "schema_version: 1\nroot: true\nprefix: app\n"

  private func run(
    _ arguments: [String],
    in folder: TemporaryFolder,
  ) async throws -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: arguments)
  }

  /// The shop with one more use case, which is only a title and so a draft.
  private func draftWorkspace() throws -> LinksWorkspace {
    let workspace = try LinksWorkspace()
    try workspace.folder.write(
      "use-cases/draft.yml",
      "prefix: draft\nuse_cases:\n  - id: wip\n    title: Work in progress\n",
    )

    return workspace
  }

  @Test
  func `a valid workspace is reported in one line, the files it read, and the next step`()
    async throws
  {
    let workspace = try draftWorkspace()

    let result = await workspace.run(["validate"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      result.outputLines == [
        "✓ valid · 6 use cases (5 ready, 1 draft) · 1 link · 4 files",
        "→ use-cases status",
      ],
    )
  }

  @Test
  func `quiet leaves out the hint`() async throws {
    let workspace = try draftWorkspace()

    let result = await workspace.run(["validate", "--quiet"])

    #expect(result.outputLines == ["✓ valid · 6 use cases (5 ready, 1 draft) · 1 link · 4 files"])
  }

  @Test
  func `a workspace with nothing in it is valid and says so`() async throws {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)

    let result = try await run(["validate", "--quiet"], in: folder)

    #expect(result.exitCode == 0)
    #expect(result.outputLines == ["✓ valid · 0 use cases (0 ready, 0 draft) · 0 links · 0 files"])
  }

  @Test
  func `one of each is counted in the singular`() async throws {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)
    try folder.write(
      "use-cases/one.yml",
      "use_cases:\n  - id: only\n    title: Only\n    value_tier: core\n    intent: It works.\n"
        + "    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
        + "    validation:\n      - id: check\n        type: { kind: unit }\n        covers: [s]\n",
    )
    try folder.write(
      "src/a.swift",
      "// @use-case:app.only#top\nwork()\n// @use-case:end app.only#top\n",
    )

    let result = try await run(["validate", "--quiet"], in: folder)

    #expect(result.outputLines == ["✓ valid · 1 use case (1 ready, 0 draft) · 1 link · 1 file"])
  }

  @Test
  func `the json report counts the same and lists the files read`() async throws {
    let workspace = try draftWorkspace()

    let document = try await workspace.run(["--json", "validate"]).document()

    #expect(document["command"] == .string("validate"))
    #expect(document["valid"] == .boolean(true))
    #expect(document["use_cases"] == .integer(6))
    #expect(document["ready"] == .integer(5))
    #expect(document["draft"] == .integer(1))
    #expect(document["links"] == .integer(1))
    #expect(
      document["files"] == .array([
        .string("use-cases/cart.yml"),
        .string("use-cases/draft.yml"),
        .string("use-cases/pay.yml"),
        .string("use-cases/top.yml"),
      ]),
    )
    #expect(document["warnings"] == .array([]))
  }

  @Test
  func `a warning is listed and never fails validate`() async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write("src/a.swift", "// @use-case:BAD\n")

    let human = await workspace.run(["validate"])
    let scripted = try await workspace.run(["--json", "validate"]).document()

    #expect(human.exitCode == 0)
    #expect(human.outputLines.count == 3)
    #expect(human.outputLines[1].hasPrefix("warning: src/a.swift:1: "))
    #expect(human.outputLines[2] == "→ use-cases status")
    guard case let .array(warnings)? = scripted["warnings"] else {
      Issue.record("no warnings")
      return
    }

    #expect(warnings.count == 1)
  }

  @Test
  func `validate runs no test and writes nothing`() async throws {
    let workspace = try LinksWorkspace()

    _ = await workspace.run(["validate"])
    _ = await workspace.run(["--json", "validate"])

    #expect(!workspace.hasStore)
  }

  @Test
  func `a valid groups file validates, and its warnings are listed beside the others`(
  ) async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  money:\n    include: { prefixes: [shop.nothing] }\n",
    )

    let human = await workspace.run(["validate"])
    let scripted = try await workspace.run(["--json", "validate"]).document()

    #expect(human.exitCode == 0)
    #expect(human.standardOutput.contains("warning: use-case-groups.yml: "))
    #expect(human.standardOutput.contains("matches nothing"))
    #expect(human.standardOutput.contains("group 'money' has no members"))
    guard case let .array(warnings)? = scripted["warnings"] else {
      Issue.record("no warnings")
      return
    }

    #expect(warnings.count >= 2)
  }

  @Test(arguments: [
    ["validate"],
    ["status"],
    ["links"],
    ["record", "shop.pay.card", "unit-tests", "pass"],
    ["verify", "--start"],
  ])
  func `an invalid groups file is refused by every command, never ignored`(
    arguments: [String],
  ) async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write("use-case-groups.yml", "schema_version: 1\n")

    let result = await workspace.run(["--json"] + arguments)
    let found = try result.document()

    #expect(result.exitCode == 2)
    #expect(found["error"]?["kind"] == .string("invalid"))
    #expect(result.standardError.contains("use-case-groups.yml: 'groups' is a required property"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a groups problem and a marker problem are raised together`() async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write("use-case-groups.yml", "schema_version: 1\n")
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay.card#x\nwork()\n")

    let result = await workspace.run(["validate"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("use-case-groups.yml: 'groups' is a required property"))
    #expect(result.standardError.contains("src/a.swift"))
    #expect(result.standardError.contains("never closed"))
  }

  @Test
  func `a broken use case file leaves the groups file checked for its structure only`(
  ) async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write("use-cases/broken.yml", "use_cases: 5\n")
    try workspace.folder.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  g:\n    include: { ids: [shop.broken.thing] }\n",
    )

    let result = await workspace.run(["validate"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("use-cases/broken.yml"))
    #expect(!result.standardError.contains("no use case"))
  }

  @Test
  func `an invalid workspace lists each problem on its own line, in order, and exits 2`(
  ) async throws {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)
    try folder.write("use-cases/b.yml", "use_cases: [\n")
    try folder.write("use-cases/a.yml", "use_cases: 5\n")

    let result = try await run(["validate"], in: folder)
    let lines = result.standardError.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(lines.count == 2)
    #expect(lines.first?.hasPrefix("error: use-cases/a.yml: ") == true)
    #expect(lines.last?.hasPrefix("use-cases/b.yml:") == true)
  }

  @Test
  func `with json the refusal is also a document of kind invalid carrying the same message`() async
    throws
  {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)
    try folder.write("use-cases/a.yml", "jobs: {}\n")

    let result = try await run(["--json", "validate"], in: folder)
    let found = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
    )
    let error = try #require(found["error"] as? [String: String])
    let message = try #require(error["message"])

    #expect(result.exitCode == 2)
    #expect(found["command"] as? String == "validate")
    #expect(error["kind"] == "invalid")
    #expect(message.hasPrefix("use-cases/a.yml: "))
    #expect(result.standardError.contains(message))
  }

  @Test
  func `validate finds the root from a folder below it`() async throws {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)
    try folder.write("src/deep/file.txt", "x")

    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url.appendingPathComponent("src/deep"),
    ).run(arguments: ["validate"])

    #expect(result.exitCode == 0)
  }

  @Test
  func `a folder with no root above it is refused with a way forward, as invalid`() async throws {
    let folder = try TemporaryFolder()

    let result = try await run(["--json", "validate"], in: folder)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use-cases.yml with root: true"))
    #expect(result.standardError.contains("use-cases init"))
    #expect(result.standardOutput.contains("\"kind\" : \"invalid\""))
  }

  @Test
  func `naming a child scope with workspace is refused`() async throws {
    let folder = try TemporaryFolder()
    try folder.write("use-cases.yml", Self.root)
    try folder.write("svc/use-cases.yml", "schema_version: 1\nprefix: svc\n")

    let result = try await run(["--workspace", "svc", "validate"], in: folder)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("child scope"))
  }

  @Test
  func `a loader that cannot load its schemas is a refusal, not an invalid workspace`() async {
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading(.schemasUnavailable(message: "no schemas")),
      workingDirectory: URL(fileURLWithPath: "/nowhere"),
    ).run(arguments: ["--json", "validate"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.contains("\"kind\" : \"refused\""))
    #expect(result.standardError == "error: no schemas\n")
  }

  @Test
  func `a link problem refuses validate as invalid, with the problems one per line`() async throws {
    let workspace = try LinksWorkspace()
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay#top\nwork()\n")
    try workspace.folder.write("src/b.swift", "// @use-case:end shop.pay#top\n")

    let result = await workspace.run(["--json", "validate"])
    let found = try result.document()
    let lines = result.standardError.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 2)
    #expect(found["command"] == .string("validate"))
    #expect(found["error"]?["kind"] == .string("invalid"))
    #expect(lines.count == 2)
    #expect(lines.first?.hasPrefix("error: src/a.swift:1: ") == true)
    #expect(lines.last?.hasPrefix("src/b.swift:1: ") == true)
  }
}
