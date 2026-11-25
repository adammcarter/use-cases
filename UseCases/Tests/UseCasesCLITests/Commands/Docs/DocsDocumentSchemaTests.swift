import Testing
import UseCasesCore
@testable import UseCasesCLI

struct DocsDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-docs.schema.json"

  private let folder: TemporaryFolder

  init() throws {
    folder = try TemporaryFolder()
  }

  private func document(_ arguments: [String]) async throws -> JSONValue {
    try await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: ["--json", "docs"] + arguments).document()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    [], ["quirks"], ["stale"], ["the", "--page-size", "1"], ["spaceship"],
    ["\"need quotes\"", "stlae", "--exact"],
  ])
  func `the docs document follows the published schema`(arguments: [String]) async throws {
    let document = try await document(arguments)

    #expect(try failures(of: document) == [])
  }

  @Test
  func `each view says which it is`() async throws {
    #expect(try await document([])["view"] == .string("list"))
    #expect(try await document(["quirks"])["view"] == .string("guide"))
    #expect(try await document(["stale"])["view"] == .string("search"))
  }

  @Test
  func `a page with a next token follows the schema too`() async throws {
    let document = try await document(["the", "--page-size", "1"])

    #expect(document["next"] != .null)
    #expect(try failures(of: document) == [])
  }

  @Test
  func `a refusal is a document of the error schema`() async throws {
    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: ["--json", "docs", "--next", "garbage"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  /// The search document with one member changed.
  private func searchDocument(
    changing member: String,
    to value: JSONValue,
  ) async throws -> JSONValue {
    guard case var .object(members) = try await document(["stale"]) else {
      throw NotADocument()
    }

    members[member] = value

    return .object(members)
  }

  @Test(arguments: [
    ("next", JSONValue.string("not a token!")),
    ("page_size", .integer(101)),
    ("total", .integer(-1)),
    ("extra", .boolean(true)),
    ("view", .string("page")),
    ("matches", .array([.object(["guide": .string("Quirks")])])),
  ])
  func `the schema check fails a docs document that breaks the schema`(
    member: String,
    value: JSONValue,
  ) async throws {
    let broken = try await searchDocument(
      changing: member,
      to: value,
    )

    #expect(try failures(of: broken) != [])
  }

  @Test(arguments: [
    ("score", JSONValue.number(0)),
    ("text", .string(String(repeating: "a", count: 161))),
    ("text", .string("")),
    ("score", .number(1.5)),
  ])
  func `a text of 161 characters or a score of nothing breaks the schema`(
    member: String,
    value: JSONValue,
  ) async throws {
    guard
      case let .array(matches)? = try await document(["stale"])["matches"],
      case var .object(match)? = matches.first
    else {
      throw NotADocument()
    }

    match[member] = value

    let broken = try await searchDocument(
      changing: "matches",
      to: .array([.object(match)]),
    )

    #expect(try failures(of: broken) != [])
  }

  private struct NotADocument: Error {}
}
