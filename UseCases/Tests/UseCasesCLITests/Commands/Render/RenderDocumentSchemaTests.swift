import Testing
@testable import UseCasesCLI

struct RenderDocumentSchemaTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
    try workspace.folder.write(
      "proposal.yml",
      """
      title: Wallet and refunds
      remove: [shop.pay.gift]
      save:
        - id: shop.pay.wallet
          title: Wallet, retitled
          value_tier: critical
          intent: The wallet pays first.
          out_of_scope: [Splitting a payment.]
          scenarios:
            - id: first
              when: [The person pays.]
              then: [The wallet is charged.]
          validation:
            - id: check
              type: { kind: unit }
              covers: [first]
        - id: shop.refunds.partial
          title: Refund part
      untouched: [shop.pay.card]
      you_see: { shop.pay.wallet: the wallet charged first }
      decisions: [{ question: how long, options: [a day, a week] }]
      """,
    )
    try workspace.folder.write("intent.yml", "what: x\nwhy: y\n")
  }

  private let schema = "schemas/output/cli-render.schema.json"

  private func failures(
    _ kind: String,
    file: String = "proposal.yml",
  ) async throws -> [String] {
    let result = await workspace.run(["--json", "render", kind, "--file", file])

    #expect(result.exitCode == 0)

    return try PublishedSchema(path: schema).failures(of: result.document())
  }

  @Test(arguments: ["brief", "proposal"])
  func `the layouts of a proposal follow the published schema`(kind: String) async throws {
    #expect(try await failures(kind) == [])
  }

  @Test
  func `the intent follows the published schema, with who left out`() async throws {
    #expect(try await failures("intent", file: "intent.yml") == [])

    let document = await workspace.run(["--json", "render", "intent", "--file", "intent.yml"])

    #expect(try document.document()["model"]?["who"] == .array([]))
  }

  @Test
  func `the results follow the published schema, a draft and a removed use case included`(
  ) async throws {
    _ = await workspace.run(["apply", "--file", "proposal.yml"])

    #expect(try await failures("results") == [])
  }

  @Test
  func `a refusal is a document of the error schema, with the command that was refused`(
  ) async throws {
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")
    let refused = await workspace.run(["--json", "render", "results", "--file", "proposal.yml"])

    #expect(refused.exitCode == 2)
    #expect(try schema.failures(of: refused.document()) == [])
    #expect(try refused.document()["command"] == .string("render"))
  }

  @Test
  func `the schema check fails a render document that breaks the schema`() async throws {
    let document = await workspace.run(["--json", "render", "proposal", "--file", "proposal.yml"])
    guard case var .object(members) = try document.document() else {
      Issue.record("not a document")
      return
    }

    members["kind"] = .string("poster")
    members["extra"] = .string("x")

    #expect(try PublishedSchema(path: schema).failures(of: .object(members)).count >= 1)
  }
}
