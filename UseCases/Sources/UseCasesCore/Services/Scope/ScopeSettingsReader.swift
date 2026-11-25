/// The real ``ScopeSettingsReading``: what discovery needs from a `use-cases.yml`, taken from the
/// full configuration.
struct ScopeSettingsReader: ScopeSettingsReading {
  private let configurationLoader: any ScopeConfigurationLoading

  init(configurationLoader: any ScopeConfigurationLoading) {
    self.configurationLoader = configurationLoader
  }

  func readSettings(
    fromText text: String,
    at path: WorkspacePath,
  ) throws(ScopeSettingsError) -> ScopeSettings {
    let configuration = try configurationLoader.load(
      fromText: text,
      at: path,
    )

    return ScopeSettings(
      isRoot: configuration.declaresRoot,
      useCasesDirectory: configuration.useCasesDirectory,
      excludes: configuration.rootSettings?.discoveryExclusions ?? [],
    )
  }
}
