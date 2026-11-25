import Testing
@testable import UseCasesCore

struct WorkspaceStatusLimitingTests {
  private let workspace = StatusSamples.workspace(
    [
      StatusSamples.useCase("shop.a", .failed),
      StatusSamples.useCase("shop.b", .unverified),
      StatusSamples.useCase("shop.c", .stale),
    ],
    signOffRequired: true,
    warnings: [.note("careful")],
    hasRunCommand: true,
  )

  @Test
  func `only the named use cases remain, in their order`() {
    let limited = workspace.limited(to: ["shop.c", "shop.a"])

    #expect(limited.useCases.map(\.identifier) == ["shop.a", "shop.c"])
  }

  @Test
  func `what is said about the workspace as a whole is kept`() {
    let limited = workspace.limited(to: ["shop.b"])

    #expect(limited.warnings == workspace.warnings)
    #expect(limited.hasSealedRuns == workspace.hasSealedRuns)
    #expect(limited.signOffRequired)
    #expect(limited.hasRunCommand)
  }

  @Test
  func `the gate of the limited workspace holds the named use cases and no other`() {
    let limited = workspace.limited(to: ["shop.b"])

    #expect(limited.gate(strict: false).passed)
    #expect(limited.gate(strict: false).warning.map(\.useCase) == ["shop.b"])
    #expect(!workspace.gate(strict: false).passed)
  }

  @Test
  func `a name no use case has, or none at all, leaves nothing`() {
    #expect(workspace.limited(to: ["shop.z"]).useCases.isEmpty)
    #expect(workspace.limited(to: []).useCases.isEmpty)
  }
}
