/// Why a scope's `use-cases.yml` gave no settings.
enum ScopeSettingsLoadingError: Error, Equatable, Sendable {
  /// The file could not be read.
  case unreadable(FileSystemError)

  /// The file was read and is not valid scope settings.
  case invalid(ScopeSettingsError)
}
