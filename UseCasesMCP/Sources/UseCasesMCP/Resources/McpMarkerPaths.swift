import UseCasesCore

/// Where a marker-based resource reads from: the `markerPaths` of
/// packages/mcp/src/resources.ts, which are the CLI's defaults with no flag to
/// override them — a resource is not configurable.
struct McpMarkerPaths {
  let productRoot: String
  let bindingsPath: String
  let evidencePath: String

  init(_ workspace: ResolvedWorkspaceContext) {
    productRoot = workspace.workspaceRoot
    bindingsPath = NodePath.join(workspace.dataRoot, ".use-cases", "bindings.jsonl")
    evidencePath = NodePath.join(workspace.dataRoot, ".use-cases", "proofs.jsonl")
  }
}
