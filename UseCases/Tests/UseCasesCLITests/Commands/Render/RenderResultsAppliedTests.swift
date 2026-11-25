import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// `render results` draws a proposal only once the workspace holds what it saves.
struct RenderResultsAppliedTests {
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

  private static let resultsProposal = """
  title: Wallet
  save:
    - id: shop.pay.wallet
      title: Wallet, retitled
      value_tier: core
      intent: The wallet pays first.
  """

  @Test
  func `a proposal that only changes a use case is not drawn as results before it is applied`(
  ) async throws {
    try workspace.folder.write("change.yml", Self.resultsProposal)

    let before = await render("results", file: "change.yml")
    let applied = await workspace.run(["apply", "--file", "change.yml"])
    let after = await render("results", file: "change.yml")

    #expect(before.exitCode == 2)
    #expect(before.standardOutput.isEmpty)
    #expect(before.standardError.contains("'shop.pay.wallet' is not as the proposal leaves it"))
    #expect(applied.exitCode == 0)
    #expect(after.exitCode == 0)
    #expect(after.standardOutput.contains("Wallet, retitled"))
  }

  @Test
  func `after the apply a route edit still draws and a title edit does not`() async throws {
    try workspace.folder.write("change.yml", Self.resultsProposal)
    _ = await workspace.run(["apply", "--file", "change.yml"])

    let path = "use-cases/pay.yml"
    let text = try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )

    try workspace.folder.write(
      path,
      text.replacingOccurrences(of: "Check it.", with: "Look at it."),
    )
    let routeEdited = await render("results", file: "change.yml")

    try workspace.folder.write(
      path,
      text.replacingOccurrences(of: "Wallet, retitled", with: "Wallet, again"),
    )
    let titleEdited = await render("results", file: "change.yml")

    #expect(routeEdited.exitCode == 0)
    #expect(titleEdited.exitCode == 2)
    #expect(titleEdited.standardError
      .contains("'shop.pay.wallet' is not as the proposal leaves it"))
  }
}
