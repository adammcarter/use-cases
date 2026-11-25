/// A `use-cases.yml` that cannot be read as scope settings, with every problem found in it.
struct ScopeSettingsError: Error, Equatable, Sendable {
  let problems: [ScopeSettingsProblem]
}
