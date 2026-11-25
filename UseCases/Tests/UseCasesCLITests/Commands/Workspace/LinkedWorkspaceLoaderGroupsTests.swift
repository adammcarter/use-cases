import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct LinkedWorkspaceLoaderGroupsTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  /// Why the workspace is refused; `nil` when it loads.
  private func failure(
    of transformers: any TransformerLinkProviding,
  ) async -> LinkedWorkspaceError? {
    do {
      _ = try await LinkedWorkspaceLoader(
        loader: WorkspaceLoader(),
        transformers: transformers,
        resolver: LinkResolver(),
      ).load(from: .workspace(workspace.folder.url))

      return nil
    } catch {
      return error
    }
  }

  @Test
  func `a workspace INVALID in its groups asks no transformer, and still finds its link problems`(
  ) async throws {
    try workspace.writeLinksProgram("tools/links", responding: "{}")
    try workspace.folder.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nlinks:\n  - transformer: tools/links\n",
    )
    try workspace.folder.write("use-case-groups.yml", "schema_version: 1\n")
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay.card#x\nwork()\n")

    let refusal = await confirmation(expectedCount: 0) { asked in
      let transformers = MockTransformerLinks { _ in
        asked()
        return .success(.none)
      }

      return await failure(of: transformers)
    }

    #expect(refusal?.refusalKind == .invalid)
    #expect(refusal?.message
      .contains("use-case-groups.yml: 'groups' is a required property") == true)
    #expect(refusal?.message.contains("src/a.swift") == true)
  }
}
