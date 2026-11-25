import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Who signs a proposal, and what is said of the use cases it leaves alone.
struct RenderSignOffTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func render(
    _ kind: String,
    file: String,
  ) async -> CommandResult {
    await workspace.run(["render", kind, "--file", file])
  }

  @Test
  func `what the person will see of an untouched use case is drawn on its line`() async throws {
    try workspace.folder.write(
      "seen.yml",
      "title: T\nremove: [shop.pay.gift]\nuntouched: [shop.pay.card]\n"
        + "you_see: { shop.pay.card: nothing changes }\n",
    )

    let result = await render("proposal", file: "seen.yml")

    #expect(result.exitCode == 0)
    #expect(result.outputLines.contains("  = UNTOUCHED  Card   you'll see: nothing changes"))
  }

  @Test
  func `an id listed untouched twice is a usage refusal`() async throws {
    try workspace.folder.write(
      "twice.yml",
      "title: T\nremove: [shop.pay.gift]\nuntouched: [shop.pay.card, shop.pay.card]\n",
    )

    let result = await render("proposal", file: "twice.yml")

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("`untouched` lists 'shop.pay.card' more than once"))
  }

  @Test
  func `a use case with no tier is the person's to sign and is counted in the document`(
  ) async throws {
    try workspace.folder.write(
      "tierless.yml",
      "title: T\nsave:\n  - id: shop.refunds.partial\n    title: R\n"
        + "  - id: shop.refunds.full\n    title: F\n    value_tier: core\n",
    )

    let result = await render("proposal", file: "tierless.yml")
    let document = try await workspace.run([
      "--json",
      "render",
      "proposal",
      "--file",
      "tierless.yml",
    ])
    .document()

    #expect(result.outputLines.contains("  SIGN-OFF     yours: 1 core, 1 without a tier"))
    #expect(document["model"]?["sign_off"] == .object([
      "core": .integer(1),
      "no_tier": .integer(1),
    ]))
    #expect(
      try PublishedSchema(path: "schemas/output/cli-render.schema.json")
        .failures(of: document) == [],
    )
  }
}
