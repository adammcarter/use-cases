extension WorkspaceLoader {
  /// The loader that reads through `fileSystem` and is the real one in everything else.
  init(reading fileSystem: any FileSystemReading) {
    self.init(
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
