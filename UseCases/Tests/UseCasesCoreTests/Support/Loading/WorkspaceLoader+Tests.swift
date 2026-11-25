@testable import UseCasesCore

extension WorkspaceLoader {
  /// The loader with everything real but the file system.
  static func reading(through fileSystem: any FileSystemReading) -> WorkspaceLoader {
    WorkspaceLoader(
      fileSystem: fileSystem,
      schemaLoader: BundledSchemaLoader(),
      yamlReader: StrictYAMLReader(),
      scopeReader: ScopeConfigurationReader(),
      technicalFieldChecker: TechnicalFieldChecker(),
      markerBindingChecker: MarkerBindingChecker(),
      definitionReader: DefinitionFileReader(),
    )
  }
}
