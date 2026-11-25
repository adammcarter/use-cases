/// Why a scope's `use-cases.yml` did not become a configuration.
enum ScopeConfigurationReadingError: Error, Equatable, Sendable {
  /// Every problem found in the file, sorted.
  case invalid([Diagnostic])
}
