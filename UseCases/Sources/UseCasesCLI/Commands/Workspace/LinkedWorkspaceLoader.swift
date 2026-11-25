import UseCasesCore

/// Loads the workspace, runs its link transformers, then resolves its links, refusing at the
/// first step that fails.
struct LinkedWorkspaceLoader: LinkedWorkspaceLoading {
  private let loader: any WorkspaceLoading
  private let transformers: any TransformerLinkProviding
  private let resolver: any LinkResolving

  init(
    loader: any WorkspaceLoading,
    transformers: any TransformerLinkProviding,
    resolver: any LinkResolving,
  ) {
    self.loader = loader
    self.transformers = transformers
    self.resolver = resolver
  }

  func load(from start: WorkspaceStart) async throws(LinkedWorkspaceError) -> LinkedWorkspace {
    let workspace: LoadedWorkspace

    do {
      workspace = try loader.load(from: start)
    } catch {
      throw .notLoaded(error)
    }

    // The links job is part of loading: a transformer that fails leaves the link set unknown, so
    // nothing is resolved from what is known (chapter 09 §20.4). A workspace that is already
    // INVALID has nothing to ask a transformer about; the problems the code itself holds are
    // still found, and raised together (chapter 09 §27).
    let transformed: TransformedLinks

    if workspace.hasHeldProblems {
      transformed = .none
    } else {
      do {
        transformed = try await transformers.links(for: workspace)
      } catch {
        throw .transformerFailed(error)
      }
    }

    let resolution = resolver.resolveLinks(
      in: workspace,
      including: transformed,
    )

    guard !resolution.isInvalid else {
      throw .invalidLinks(problems: resolution.problems)
    }

    return LinkedWorkspace(
      workspace: workspace,
      resolution: resolution,
    )
  }
}
