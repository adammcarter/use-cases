import Testing
@testable import UseCasesCLI

struct ShowDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-show.schema.json"

  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: ["shop.pay.wallet", "shop.pay.card", "shop.cart.share", "shop.cart.add"])
  func `the show document of every use case follows the published schema`(
    identifier: String,
  ) async throws {
    let document = try await workspace.run(["--json", "show", identifier]).document()

    #expect(try failures(of: document) == [])
    #expect(document["approval"] != nil)
  }

  @Test
  func `the document holds what the schema's samples need, so the check is not empty`(
  ) async throws {
    let document = try await workspace.run(["--json", "show", "shop.pay.card"]).document()

    #expect(document["definition"]?["validation"] != nil)
    #expect(document["definition"]?["scenarios"] != nil)
  }

  @Test
  func `a refusal is a document of the error schema`() async throws {
    let result = await workspace.run(["--json", "show", "shop.pay.nope"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails a show document that breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "show", "shop.pay.wallet"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["state"] = .string("INVALID")
    members["extra"] = .boolean(true)
    members["missing"] = .array([.string("")])
    members["use_case"] = .string("Not An Id")

    #expect(try failures(of: .object(members)).count >= 4)
  }
}
