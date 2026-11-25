import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct LinkedWorkspaceLoaderTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  private func loader(
    _ loading: any WorkspaceLoading = WorkspaceLoader(),
  ) -> LinkedWorkspaceLoader {
    LinkedWorkspaceLoader(
      loader: loading,
      transformers: MockTransformerLinks.none,
      resolver: LinkResolver(),
    )
  }

  @Test
  func `a workspace whose links resolve is loaded with them`() async throws {
    try workspace.folder.write("src/a.swift", LinksWorkspace.marked("shop.pay#top"))

    let linked = try await loader().load(from: .workspace(workspace.folder.url))

    #expect(
      linked.resolution.links.map(\.key) == [
        "shop.cart.add#config@config/cart.yml:1",
        "shop.pay#top@src/a.swift:2",
      ],
    )
  }

  @Test
  func `a workspace that does not load is refused as the loader refuses it`() async {
    let refusal = WorkspaceLoadingError.schemasUnavailable(message: "no schemas")

    await #expect(throws: LinkedWorkspaceError.notLoaded(refusal)) {
      try await loader(MockWorkspaceLoading(refusal)).load(from: .workspace(workspace.folder.url))
    }
    #expect(LinkedWorkspaceError.notLoaded(refusal).refusalKind == .refused)
    #expect(LinkedWorkspaceError.notLoaded(refusal).message == "no schemas")
  }

  @Test
  func `a link problem refuses the workspace as invalid, a problem to a line`() async throws {
    try workspace.folder.write("src/a.swift", "// \(MarkerText.sentinel)shop.pay#top\nwork()\n")

    await #expect(throws: LinkedWorkspaceError.self) {
      try await loader().load(from: .workspace(workspace.folder.url))
    }

    do {
      _ = try await loader().load(from: .workspace(workspace.folder.url))
    } catch {
      #expect(error.refusalKind == .invalid)
      #expect(error.message.hasPrefix("src/a.swift:1: "))
      #expect(!error.message.contains("\n"))
    }
  }
}
