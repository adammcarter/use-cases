import Foundation
import Testing
@testable import UseCasesCLI

/// Every transformer exchange is checked against the published schemas (ADR 037): here the
/// request the core writes, read back from a program that kept it.
struct TransformerRequestSchemaTests {
  private static let schemaPath = "schemas/engine/transformer-links-request.schema.json"
  private static let answer = "{\"contract\":1,\"links\":[],\"diagnostics\":[]}"

  private let workspace: LinksWorkspace
  private let kept: URL

  init() throws {
    workspace = try LinksWorkspace()
    kept = FileManager.default.temporaryDirectory
      .appendingPathComponent("request-\(UUID().uuidString).json")
  }

  private func request(settings: String = "") async throws -> JSONValue {
    try workspace.writeLinksProgram(
      "tools/links",
      responding: Self.answer,
      keepingRequestAt: kept,
    )
    try workspace.folder.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nlinks:\n  - transformer: tools/links\n" + settings,
    )

    let result = await workspace.run(["links", "--quiet"])
    defer {
      try? FileManager.default.removeItem(at: kept)
    }

    #expect(result.exitCode == 0)

    return try JSONDecoder().decode(
      JSONValue.self,
      from: Data(contentsOf: kept),
    )
  }

  @Test
  func `the request follows the published schema`() async throws {
    let request = try await request()

    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: request) == [])
  }

  @Test
  func `settings of every JSON type go through, and the request still follows the schema`()
    async throws
  {
    let request = try await request(
      settings: "    settings:\n      files: \"test/**/*.js\"\n      strict: true\n"
        + "      limit: 5\n      ratio: 0.5\n      nothing: null\n      list: [a, 1]\n",
    )

    let settings = try #require(request["settings"])

    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: request) == [])
    #expect(settings["strict"] == .boolean(true))
    #expect(settings["limit"] == .integer(5))
    #expect(settings["nothing"] == .null)
    #expect(settings["files"] == .string("test/**/*.js"))
  }

  @Test
  func `it names every use case with the routes and the workspace it asks about`() async throws {
    let request = try await request()

    guard case let .array(useCases)? = request["use_cases"] else {
      Issue.record("no use cases")
      return
    }

    let ids = useCases.compactMap { useCase -> String? in
      guard case let .string(id)? = useCase["id"] else {
        return nil
      }

      return id
    }

    #expect(
      ids.sorted() == [
        "shop.cart.add", "shop.cart.share", "shop.pay", "shop.pay.card", "shop.pay.wallet",
      ],
    )
    #expect(useCases.allSatisfy { $0["validation"] != nil })
    // The root is the canonical one, which may spell a system folder differently.
    guard case let .string(root)? = request["code_root"] else {
      Issue.record("no code_root")
      return
    }

    #expect(root.hasSuffix(workspace.folder.url.lastPathComponent))
    #expect(request["ignore"] != nil)
  }
}
