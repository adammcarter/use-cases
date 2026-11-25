/// Everything one judging reads, worked out once: the workspace, what its links cover, the empty
/// regions among their warnings, the fingerprints now and the history of the store.
struct StatusInputs {
  let workspace: LoadedWorkspace
  let links: LinkResolution
  let fingerprints: RouteFingerprints
  let history: StoreHistory
  let coverage: LinkCoverage
  let emptyRegions: [EmptyMarkerRegion]

  init(
    workspace: LoadedWorkspace,
    links: LinkResolution,
    fingerprints: RouteFingerprints,
    history: StoreHistory,
  ) {
    self.workspace = workspace
    self.links = links
    self.fingerprints = fingerprints
    self.history = history
    coverage = LinkCoverage(links.links)
    emptyRegions = links.emptyMarkerRegions
  }
}
