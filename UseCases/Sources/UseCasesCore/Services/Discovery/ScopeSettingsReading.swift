/// Reads one scope's `use-cases.yml` into the settings discovery acts on. The real reader
/// (YAML, schema, defaults) plugs in here; discovery never parses YAML itself.
protocol ScopeSettingsReading: Sendable {
  /// The settings in `text`, the content of the file at `path` (workspace-relative, so
  /// `use-cases.yml` for the root's).
  func readSettings(
    fromText text: String,
    at path: WorkspacePath,
  ) throws(ScopeSettingsError) -> ScopeSettings
}
