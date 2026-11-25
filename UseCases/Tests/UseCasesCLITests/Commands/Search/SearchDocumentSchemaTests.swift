import Testing
@testable import UseCasesCLI

struct SearchDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-search.schema.json"

  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    ["wallet"],
    ["shop", "--page-size", "2"],
    ["shop", "--full"],
    ["spaceship"],
    ["card", "--state", "unverified", "--tier", "core", "--in", "title,intent"],
    ["\"shop pay\"", "wallet", "--exact"],
  ])
  func `the search document follows the published schema`(arguments: [String]) async throws {
    let document = try await workspace.run(["--json", "search"] + arguments).document()

    #expect(try failures(of: document) == [])
  }

  @Test
  func `a page with a next token follows the schema too`() async throws {
    let document = try await workspace.run(["--json", "search", "shop", "--page-size", "1"])
      .document()

    #expect(document["next"] != .null)
    #expect(try failures(of: document) == [])
  }

  @Test
  func `a refusal is a document of the error schema`() async throws {
    let result = await workspace.run(["--json", "search", "x", "--in", "tags"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails a search document that breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "search", "wallet"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["next"] = .string("not a token!")
    members["page_size"] = .integer(101)
    members["extra"] = .boolean(true)
    members["total"] = .integer(-1)

    #expect(try failures(of: .object(members)).count >= 4)
  }

  @Test
  func `a score of nothing or a reason of 161 characters breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "search", "wallet"]).document()
    guard
      case var .object(members) = document,
      case let .array(matches)? = document["matches"],
      case var .object(match)? = matches.first
    else {
      Issue.record("not a document")
      return
    }

    match["score"] = .number(0)
    match["why"] = .array([.object([
      "field": .string("title"),
      "text": .string(String(repeating: "a", count: 161)),
    ])])
    members["matches"] = .array([.object(match)])

    #expect(try failures(of: .object(members)).count >= 2)
  }
}
