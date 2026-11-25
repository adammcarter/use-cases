import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct InitCommandTests {
  private static let everything = [
    "use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml",
  ]

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  private func entries(of document: JSONValue) -> [JSONValue] {
    guard case let .array(entries)? = document["use_cases"] else {
      return []
    }

    return entries
  }

  // MARK: - What it makes

  @Test
  func `an empty folder under git gets the files and one next step`() async throws {
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")

    let result = await place.run(["init", "--no-input"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      result.outputLines == [
        "created  use-cases.yml",
        "created  use-cases/example.yml      a DRAFT example: fill it in, or delete it",
        "created  use-case-groups.yml",
        "created  use-cases-bridge.yml       a commented template: add your own test command",
        "added    .use-cases/ to .gitignore",
        "→ use-cases status",
      ],
    )
    #expect(try place.read(".gitignore") == ".use-cases/\n")
  }

  @Test
  func `without version control it says so in a note before the next step`() async {
    let result = await place.run(["init", "--no-input"])

    #expect(result.outputLines.count == 6)
    #expect(result.outputLines[4].hasPrefix("note: no version control found here"))
    #expect(result.outputLines.last == "→ use-cases status")
  }

  @Test
  func `quiet leaves out the hint`() async {
    let result = await place.run(["init", "--no-input", "--quiet"])

    #expect(result.outputLines.last?.hasPrefix("→") == false)
  }

  @Test
  func `the files it made are a workspace that validates at once`() async {
    _ = await place.run(["init", "--no-input"])

    let result = await place.run(["validate", "--quiet"])

    #expect(result.outputLines == ["✓ valid · 1 use case (0 ready, 1 draft) · 0 links · 1 file"])
  }

  @Test
  func `minimal writes the workspace file alone`() async throws {
    let result = await place.run(["--json", "init", "--minimal"])

    #expect(try result.document()["created"]?.strings == ["use-cases.yml"])
    #expect(try place.snapshot().keys.sorted() == ["use-cases.yml"])
  }

  @Test
  func `a prefix is written and the example's id starts with it`() async throws {
    let result = await place.run(["init", "--no-input", "--prefix", "shop"])
    let status = try await place.run(["--json", "status"]).document()

    #expect(result.exitCode == 0)
    #expect(try place.read("use-cases.yml").contains("\nprefix: shop\n"))
    #expect(
      JSONValue.array(entries(of: status).compactMap { entry in entry["use_case"] }).strings
        == ["shop.example.getting-started"],
    )
    #expect(try place.read("use-case-groups.yml").contains("- shop.example\n"))
  }

  @Test
  func `the example is in the group, never blocks a gate, and nothing is left behind`()
    async throws
  {
    _ = await place.run(["init", "--no-input"])

    let group = try await place.run(["--json", "status", "--group", "smoke"]).document()
    let gate = await place.run(["status", "--gate", "--strict"])

    #expect(group["summary"]?["total"] == .integer(1))
    #expect(gate.exitCode == 0)
  }

  // MARK: - The document

  @Test
  func `the json document says what was made, kept and done about gitignore`() async throws {
    try place.folder.write(".gitignore", "build/\n")
    try place.folder.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")

    let document = try await place.run(["--json", "init"]).document()

    #expect(document["command"] == .string("init"))
    #expect(document["output_version"] == .integer(1))
    #expect(document["workspace"] == .string(place.realPath))
    #expect(document["created"]?.strings == [
      "use-cases.yml", "use-cases/example.yml", "use-cases-bridge.yml",
    ])
    #expect(document["kept"]?.strings == ["use-case-groups.yml"])
    #expect(document["gitignore"] == .string("added"))
    #expect(document["hooks"] == .array([]))
    #expect(document["notes"] == .array([]))
    #expect(document["dry_run"] == .boolean(false))
  }

  @Test
  func `a second run keeps every file and writes nothing`() async throws {
    try place.folder.write(".git/HEAD", "x")
    _ = await place.run(["init", "--no-input"])
    let before = try place.snapshot()

    let document = try await place.run(["--json", "init"]).document()

    #expect(document["created"] == .array([]))
    #expect(document["kept"]?.strings == Self.everything)
    #expect(document["gitignore"] == .string("present"))
    #expect(try place.snapshot() == before)
  }

  @Test
  func `a file that is there is left exactly as it is`() async throws {
    let mine = "schema_version: 1\ngroups:\n  mine:\n    include: { prefixes: [example] }\n"
    try place.folder.write("use-case-groups.yml", mine)

    let result = await place.run(["init", "--no-input"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.contains("kept     use-case-groups.yml"))
    #expect(try place.read("use-case-groups.yml") == mine)
  }

  // MARK: - Dry run

  @Test
  func `a dry run writes nothing, says would, and has no next step`() async throws {
    try place.folder.write(".git/HEAD", "x")
    let before = try place.snapshot()

    let result = await place.run(["init", "--no-input", "--dry-run"])

    #expect(result.exitCode == 0)
    #expect(
      result.outputLines == [
        "would create  use-cases.yml",
        "would create  use-cases/example.yml      a DRAFT example: fill it in, or delete it",
        "would create  use-case-groups.yml",
        "would create  use-cases-bridge.yml       a commented template: add your own test command",
        "would add     .use-cases/ to .gitignore",
      ],
    )
    #expect(try place.snapshot() == before)
  }

  @Test
  func `the document of a dry run is the one of the real run`() async throws {
    try place.folder.write(".git/HEAD", "x")

    guard case var .object(dry) = try await place.run(["--json", "init", "--dry-run"]).document(),
          case var .object(real) = try await place.run(["--json", "init"]).document()
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

  @Test
  func `a dry run refuses what the real run would refuse`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")

    let result = await place.run(["init", "--dry-run", "--prefix", "shop"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("differs from the workspace"))
  }

  // MARK: - Where it works

  @Test
  func `workspace names the folder to set up, read from where it runs`() async throws {
    try place.folder.write("services/pay/keep.txt", "x")

    let result = await place.run(
      ["--json", "--workspace", "services/pay", "init", "--minimal"],
    )

    #expect(result.exitCode == 0)
    #expect(try place.read("services/pay/use-cases.yml").contains("root: true"))
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent("use-cases.yml").path))
  }

  @Test
  func `it sets up the folder it runs in and never looks above for another`() async throws {
    try place.folder.write("services/pay/keep.txt", "x")

    let result = await place.run(
      ["init", "--no-input", "--minimal"],
      from: place.url.appendingPathComponent("services/pay"),
    )

    #expect(result.exitCode == 0)
    #expect(try place.read("services/pay/use-cases.yml").contains("root: true"))
  }
}
