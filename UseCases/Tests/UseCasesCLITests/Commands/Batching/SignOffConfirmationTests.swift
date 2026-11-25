import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The read-back: a batch or a sign-off is written only when the workspace as it would be holds
/// what it meant.
struct SignOffConfirmationTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func run(_ arguments: [String]) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      viewer: UnchangedPlanViewer(),
      workingDirectory: workspace.folder.url,
    ).run(arguments: arguments)
  }

  private func read(_ path: String) throws -> String {
    try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  private func batch(_ text: String) throws -> [String] {
    try workspace.folder.write("batch.yml", text)

    return ["apply", "--file", "batch.yml"]
  }

  @Test
  func `a batch that adds a use case the workspace would not hold is refused, and writes nothing`()
    async throws
  {
    let arguments = try batch("save:\n  - id: shop.refunds.partial\n    title: T\n")
    let before = try read("use-cases/pay.yml")

    let result = await run(arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("shop.refunds.partial is not in the workspace"))
    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent("use-cases/refunds.yml")
        .path))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a batch that removes a use case the workspace would still hold is refused`() async throws {
    let arguments = try batch("remove: [shop.pay.wallet]\n")
    let before = try read("use-cases/pay.yml")

    let result = await run(["--json"] + arguments)
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("refused"))
    #expect(document["command"] == .string("apply"))
    #expect(result.standardOutput.contains("would still be in the workspace"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a batch that changes a use case the workspace would hold as it was is refused`()
    async throws
  {
    let arguments = try batch("save:\n  - id: shop.pay.wallet\n    title: Retitled\n")
    let before = try read("use-cases/pay.yml")

    let result = await run(arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("shop.pay.wallet would not read back as it was sent"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a sign-off the workspace would not hold is refused, and writes nothing`() async throws {
    let before = try read("use-cases/pay.yml")

    let result = await run(["--json", "approve", "shop.pay.card", "--by", "Kim"])
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("refused"))
    #expect(document["command"] == .string("approve"))
    #expect(result.standardOutput.contains("shop.pay.card would not read back as it was sent"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a sign-off of everything the workspace would not hold is refused in every file`()
    async throws
  {
    let result = await run(["approve", "--all", "--by", "Kim"])

    #expect(result.exitCode == 2)
    #expect(try !read("use-cases/pay.yml").contains("approved:"))
    #expect(try !read("use-cases/cart.yml").contains("approved:"))
  }

  @Test
  func `what is already as it was meant still passes the read-back`() async throws {
    _ = await workspace.run(["approve", "shop.pay.card", "--by", "Kim"])
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let yaml = shown.enumerated().map { number, line in
      number == 0 ? "  - \(line)" : "    \(line)"
    }.joined(separator: "\n")

    let applied = try await run(batch("save:\n\(yaml)\n"))
    let approved = await run(["approve", "shop.pay.card", "--by", "Sam"])

    #expect(applied.exitCode == 0)
    #expect(approved.exitCode == 0)
  }
}
