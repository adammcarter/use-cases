import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct LinkedWorkspaceReloaderTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  private func reloader(
    _ loading: any WorkspaceLoading = WorkspaceLoader(),
    transformers: any TransformerLinkProviding = MockTransformerLinks.none,
  ) -> LinkedWorkspaceReloader {
    LinkedWorkspaceReloader(
      loader: LinkedWorkspaceLoader(
        loader: loading,
        transformers: transformers,
        resolver: LinkResolver(),
      ),
      start: .workspace(workspace.folder.url),
    )
  }

  @Test
  func `the workspace is read again from where the command began, with its links`() async throws {
    try workspace.folder.write("src/a.swift", LinksWorkspace.marked("shop.pay#top"))

    let first = try await reloader().reload()

    try workspace.folder.write("src/b.swift", LinksWorkspace.marked("shop.pay#second"))

    let second = try await reloader().reload()

    #expect(first.links.links.count == 2)
    #expect(second.links.links.count == 3)
  }

  @Test
  func `a workspace that has become invalid is told with its problems`() async {
    let refusal = WorkspaceLoadingError.invalid(problems: ["one", "two"])

    await #expect(throws: ReloadingError.invalid(problems: ["one", "two"])) {
      try await reloader(MockWorkspaceLoading(refusal)).reload()
    }
  }

  @Test
  func `a link transformer stopped by a cancellation is a cancellation`() async {
    await #expect(throws: ReloadingError.cancelled) {
      try await reloader(transformers: MockTransformerLinks.failing(.cancelled)).reload()
    }
  }
}
