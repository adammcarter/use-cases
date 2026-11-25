/// What one fingerprinting call shares between its steps: where the workspace is, the policy
/// that says how content is compared, and the way content is reduced.
struct FreshnessRun: Sendable {
  let workspace: LoadedWorkspace
  let context: DiscoveryContext
  let policy: FreshnessPolicy
  let referencer: any ContentReferencing

  /// The files the links point into. They are held whole to take the regions of them, so a
  /// resource that is one of them is referenced from what is held, and any other resource is
  /// read a chunk at a time.
  let linkedFiles: Set<WorkspacePath>

  /// Reads the root's policy, which is the standard one when the root says nothing.
  init(
    workspace: LoadedWorkspace,
    linkedFiles: Set<WorkspacePath> = [],
  ) {
    self.linkedFiles = linkedFiles
    let policy = workspace.scopes.first?.configuration.rootSettings?.freshness ?? .standard

    self.workspace = workspace
    context = workspace.discoveryContext
    self.policy = policy
    referencer = ContentReferencer(policy: policy)
  }
}
