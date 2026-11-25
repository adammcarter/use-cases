/// Loads the optional root `use-cases-bridge.yml` as part of the model (chapter 09 §21). It
/// reads the file and runs nothing.
protocol BridgeSettingsLoading: Sendable {
  /// - Parameters:
  ///   - root: The checked workspace root.
  ///   - scopes: Every scope of the workspace; a bridge file in any but the root is a problem.
  func load(
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
  ) -> BridgeLoadResult
}
