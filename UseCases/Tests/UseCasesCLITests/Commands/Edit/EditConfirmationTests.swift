import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The read-back: a change is written only when the workspace as it would be holds what the
/// change meant.
struct EditConfirmationTests {
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

  @Test
  func `a save whose use case the workspace would not hold is refused, and writes nothing`()
    async throws
  {
    try workspace.folder.write("sent.yml", "id: shop.refunds.partial\ntitle: T\n")
    let before = try read("use-cases/pay.yml")

    let result = await run(["save", "--file", "sent.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("shop.refunds.partial is not in the workspace"))
    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent("use-cases/refunds.yml")
        .path))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a remove whose use case the workspace would still hold is refused, and writes nothing`()
    async throws
  {
    let before = try read("use-cases/pay.yml")

    let result = await run(["--json", "remove", "shop.pay.wallet"])
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("refused"))
    #expect(result.standardOutput.contains("would still be in the workspace"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a save of a use case that is already there as sent still passes the read-back`(
  ) async throws {
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    try workspace.folder.write("sent.yml", shown.joined(separator: "\n") + "\n")

    let result = await run(["save", "--file", "sent.yml"])

    #expect(result.exitCode == 0)
  }
}
