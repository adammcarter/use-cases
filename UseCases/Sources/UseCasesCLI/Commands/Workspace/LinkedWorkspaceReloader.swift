import UseCasesCore

/// Reads the workspace again through the same loader the command began with: the guard of the
/// finish point needs the code as it is after the reports were read (chapter 13 §7 step 6).
struct LinkedWorkspaceReloader: WorkspaceReloading {
  private let loader: any LinkedWorkspaceLoading
  private let start: WorkspaceStart

  init(
    loader: any LinkedWorkspaceLoading,
    start: WorkspaceStart,
  ) {
    self.loader = loader
    self.start = start
  }

  func reload() async throws(ReloadingError) -> ResolvedWorkspace {
    do {
      let linked = try await loader.load(from: start)

      return ResolvedWorkspace(
        workspace: linked.workspace,
        links: linked.resolution,
      )
    } catch {
      guard error.refusalKind != nil else {
        throw .cancelled
      }

      throw .invalid(problems: error.message.split(separator: "\n").map(String.init))
    }
  }
}
