import Testing
@testable import UseCasesCLI

struct SignOffDocumentSchemaTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func failures(
    of document: JSONValue,
    command: String,
  ) throws -> [String] {
    try PublishedSchema(path: "schemas/output/cli-\(command).schema.json").failures(of: document)
  }

  @Test(arguments: [
    ("remove: [shop.pay.gift]\n", false),
    ("save:\n  - id: shop.refunds.partial\n    title: T\n", false),
    ("save:\n  - id: shop.pay.wallet\n    title: Changed\n", false),
    ("save:\n  - id: shop.pay.wallet\n    title: Changed\nremove: [shop.pay.gift]\n", true),
  ])
  func `the apply document follows the published schema`(
    batch: String,
    dryRun: Bool,
  ) async throws {
    try workspace.folder.write("batch.yml", batch)

    let result = await workspace.run(
      ["--json", "apply", "--file", "batch.yml"] + (dryRun ? ["--dry-run"] : []),
    )

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document(), command: "apply") == [])
  }

  @Test
  func `the apply document of a batch that changes nothing follows the schema too`() async throws {
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let yaml = shown.enumerated().map { number, line in
      number == 0 ? "  - \(line)" : "    \(line)"
    }.joined(separator: "\n")
    try workspace.folder.write("batch.yml", "save:\n\(yaml)\n")

    let result = await workspace.run(["--json", "apply", "--file", "batch.yml"])

    #expect(try failures(of: result.document(), command: "apply") == [])
  }

  @Test(arguments: [
    (["shop.pay.card"], false),
    (["--all"], false),
    (["shop.pay.card", "shop.cart.add"], true),
    (["--all"], true),
  ])
  func `the approve document follows the published schema`(
    selection: [String],
    dryRun: Bool,
  ) async throws {
    let result = await workspace.run(
      ["--json", "approve"] + selection + ["--by", "Kim"] + (dryRun ? ["--dry-run"] : []),
    )

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document(), command: "approve") == [])
  }

  @Test
  func `the approve document of use cases already approved follows the schema`() async throws {
    _ = await workspace.run(["approve", "--all", "--by", "Kim"])

    let result = await workspace.run(["--json", "approve", "--all", "--by", "Kim"])

    #expect(try failures(of: result.document(), command: "approve") == [])
  }

  @Test
  func `the approve document with warnings follows the published schema`() async throws {
    try workspace.folder.write(
      "use-cases/noted.yml",
      "prefix: noted\nuse_cases:\n  - id: item\n    title: Item\n    approved:\n"
        + "      # who\n      by: Sam\n      \"on\": \"2026-01-01\"\n"
        + "      behaviour: \"\(String(repeating: "0", count: 64))\"\n",
    )

    let result = await workspace.run(["--json", "approve", "shop.noted.item", "--by", "Kim"])
    let document = try result.document()

    #expect(document["warnings"]?.strings.count == 1)
    #expect(try failures(of: document, command: "approve") == [])
  }

  @Test
  func `a refusal is a document of the error schema, with the command that was refused`(
  ) async throws {
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")
    let apply = await workspace.run(["--json", "apply", "--file", "missing.yml"])
    let approve = await workspace.run(["--json", "approve", "--all", "--by", " "])

    #expect(try schema.failures(of: apply.document()) == [])
    #expect(try schema.failures(of: approve.document()) == [])
    #expect(try apply.document()["command"] == .string("apply"))
    #expect(try approve.document()["command"] == .string("approve"))
  }

  @Test
  func `the schema check fails an approve document that breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "approve", "--all", "--by", "Kim"])
      .document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["extra"] = .array([])
    members["by"] = .string("")

    #expect(try failures(of: .object(members), command: "approve").count >= 2)
  }
}
