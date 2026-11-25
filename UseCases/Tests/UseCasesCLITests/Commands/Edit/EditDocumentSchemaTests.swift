import Testing
@testable import UseCasesCLI

struct EditDocumentSchemaTests {
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
    ("id: shop.refunds.partial\ntitle: T\n", false),
    ("id: shop.pay.crypto\ntitle: T\n", false),
    ("id: shop.pay.wallet\ntitle: Changed\n", false),
    ("id: shop.refunds.partial\ntitle: T\n", true),
  ])
  func `the save document follows the published schema`(
    text: String,
    dryRun: Bool,
  ) async throws {
    try workspace.folder.write("sent.yml", text)

    let result = await workspace.run(
      ["--json", "save", "--file", "sent.yml"] + (dryRun ? ["--dry-run"] : []),
    )

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document(), command: "save") == [])
  }

  @Test
  func `the remove document follows the published schema`() async throws {
    let result = await workspace.run(["--json", "remove", "shop.pay.wallet"])

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document(), command: "remove") == [])
  }

  @Test
  func `a refusal is a document of the error schema, with the command that was refused`(
  ) async throws {
    let result = await workspace.run(["--json", "remove", "shop.pay.nope"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
    #expect(try result.document()["command"] == .string("remove"))
  }

  @Test
  func `the schema check fails a save document that breaks the schema`() async throws {
    try workspace.folder.write("sent.yml", "id: shop.refunds.partial\ntitle: T\n")
    let document = try await workspace.run(["--json", "save", "--file", "sent.yml"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["action"] = .string("removed")
    members["extra"] = .boolean(true)

    #expect(try failures(of: .object(members), command: "save").count >= 2)
  }
}
