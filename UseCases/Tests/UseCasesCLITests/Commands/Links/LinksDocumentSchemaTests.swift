import Foundation
import Testing
@testable import UseCasesCLI

struct LinksDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-links.schema.json"

  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
    try workspace.folder.write(
      "src/pay.swift",
      LinksWorkspace.marked("shop.pay#top")
        + LinksWorkspace.marked("shop.pay.card#unit-tests.charges", "check()")
        + "// @use-case:BAD\n",
    )
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    ["--json", "links"],
    ["--json", "links", "shop.pay"],
    ["--json", "links", "shop.cart.share"],
  ])
  func `the links document of every request follows the published schema`(
    arguments: [String],
  ) async throws {
    let document = try await workspace.run(arguments).document()

    #expect(try failures(of: document) == [])
  }

  @Test
  func `the document has links to check, so the schema check is not empty`() async throws {
    let document = try await workspace.run(["--json", "links"]).document()

    guard case let .array(links)? = document["links"] else {
      Issue.record("no links")
      return
    }

    #expect(links.count == 3)
    #expect(links.contains { $0["route"] != nil })
    #expect(links.contains { $0["route"] == nil })
  }

  @Test
  func `a refusal is a document of the error schema`() async throws {
    let result = await workspace.run(["--json", "links", "shop.nope"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails a document that breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "links"]).document()
    guard case var .object(members) = document, case var .array(links)? = members["links"],
          case var .object(first) = links[0]
    else {
      Issue.record("not a links document")
      return
    }

    first["route"] = .null
    first["bytes"] = .integer(3)
    first["role"] = .string("both")
    first["range"] = .object(["start": .integer(0), "end": .integer(1)])
    links[0] = .object(first)
    members["links"] = .array(links)
    members["diagnostics"] = .array([.string("")])
    members["output_version"] = .integer(2)

    let broken = try failures(of: .object(members))

    #expect(broken.count >= 6)
  }
}
