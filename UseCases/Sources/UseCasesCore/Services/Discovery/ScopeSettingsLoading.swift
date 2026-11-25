import Foundation

/// Reads a scope's `use-cases.yml` from disk into its settings.
protocol ScopeSettingsLoading: Sendable {
  /// The settings in the file at `file`, whose workspace-relative spelling is `path`.
  func loadSettings(
    at file: URL,
    path: WorkspacePath,
  ) throws(ScopeSettingsLoadingError) -> ScopeSettings
}
