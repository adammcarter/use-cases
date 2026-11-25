/// Turns the text of a scope's `use-cases.yml` into its configuration: YAML, the workspace
/// schema, then the configuration reader (chapter 09 §5, §8, §9).
protocol ScopeConfigurationLoading: Sendable {
  /// The configuration with its defaults filled in, or every problem in the file.
  ///
  /// - Parameters:
  ///   - text: The content of the file.
  ///   - path: The file, workspace-relative; every problem names it. A file that is not at the
  ///     top of the workspace is a child scope's, unless it says `root: true`: that is a nested
  ///     workspace, which holds root-only settings of its own.
  func load(
    fromText text: String,
    at path: WorkspacePath,
  ) throws(ScopeSettingsError) -> ScopeConfiguration
}
