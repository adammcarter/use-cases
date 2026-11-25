import Foundation

extension WorkspaceLoader: WorkspaceRootLocating {
  public func locateRoot(from start: WorkspaceStart) throws(WorkspaceLoadingError) -> URL {
    let schemas = try loadSchemas()
    let configurationLoader = ScopeConfigurationLoader(
      yamlReader: yamlReader,
      schema: schemas.workspace,
      configurationReader: scopeReader,
    )

    return try findRoot(
      from: start,
      settingsLoader: ScopeSettingsLoader(
        fileSystem: fileSystem,
        settingsReader: ScopeSettingsReader(configurationLoader: configurationLoader),
      ),
    ).directory
  }
}
