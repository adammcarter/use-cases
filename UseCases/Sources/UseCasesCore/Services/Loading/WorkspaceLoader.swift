import Foundation

/// Loads a workspace from the file system (chapter 09 §34): the root, the scopes, every
/// definition file, the full ids, and the checks that need the whole workspace.
public struct WorkspaceLoader: WorkspaceLoading {
  let fileSystem: any FileSystemReading
  let schemaLoader: any SchemaLoading
  let yamlReader: any YAMLReading
  let scopeReader: any ScopeConfigurationReading
  let technicalFieldChecker: any TechnicalFieldChecking
  let markerBindingChecker: any MarkerBindingChecking
  let definitionReader: any DefinitionFileReading

  /// Makes the loader that reads the real file system with the schemas bundled in this build.
  public init() {
    self.init(
      fileSystem: LocalFileSystem(),
      schemaLoader: BundledSchemaLoader(),
      yamlReader: StrictYAMLReader(),
      scopeReader: ScopeConfigurationReader(),
      technicalFieldChecker: TechnicalFieldChecker(),
      markerBindingChecker: MarkerBindingChecker(),
      definitionReader: DefinitionFileReader(),
    )
  }

  init(
    fileSystem: any FileSystemReading,
    schemaLoader: any SchemaLoading,
    yamlReader: any YAMLReading,
    scopeReader: any ScopeConfigurationReading,
    technicalFieldChecker: any TechnicalFieldChecking,
    markerBindingChecker: any MarkerBindingChecking,
    definitionReader: any DefinitionFileReading,
  ) {
    self.fileSystem = fileSystem
    self.schemaLoader = schemaLoader
    self.yamlReader = yamlReader
    self.scopeReader = scopeReader
    self.technicalFieldChecker = technicalFieldChecker
    self.markerBindingChecker = markerBindingChecker
    self.definitionReader = definitionReader
  }

  /// Loads the workspace found from `start`: the root, every scope, every definition file and the
  /// full ids, reporting every independent problem found, sorted (chapter 09 §27).
  public func load(from start: WorkspaceStart) throws(WorkspaceLoadingError) -> LoadedWorkspace {
    let schemas = try loadSchemas()
    let configurationLoader = ScopeConfigurationLoader(
      yamlReader: yamlReader,
      schema: schemas.workspace,
      configurationReader: scopeReader,
    )
    let settingsLoader = ScopeSettingsLoader(
      fileSystem: fileSystem,
      settingsReader: ScopeSettingsReader(configurationLoader: configurationLoader),
    )

    let root = try findRoot(
      from: start,
      settingsLoader: settingsLoader,
    )
    let discovery = WorkspaceDiscoverer(
      fileSystem: fileSystem,
      settingsLoader: settingsLoader,
    ).discover(root: root)

    var diagnostics = discovery.diagnostics
    let scopes = loadScopes(
      of: discovery,
      root: root,
      configurationLoader: configurationLoader,
      diagnostics: &diagnostics,
    )
    let useCases = loadUseCases(
      in: scopes,
      root: root,
      uncertainBelow: discovery.unreadableScopes,
      definitionLoader: definitionLoader(checkingWith: schemas.useCases),
      diagnostics: &diagnostics,
    )
    diagnostics += duplicateDiagnostics(among: useCases)

    let rootFiles = loadRootFiles(
      in: root,
      scopes: scopes,
      useCases: useCases,
      schemas: schemas,
      diagnostics: &diagnostics,
    )

    return try LoadedWorkspace(
      root: root.directory,
      scopes: scopes,
      useCases: useCases,
      warnings: warnings(of: diagnostics),
      bridge: rootFiles.bridge,
      groups: rootFiles.groups,
      rootFileWarnings: rootFiles.warnings,
      heldProblems: rootFiles.groupProblems,
    )
  }

  private func definitionLoader(checkingWith schema: any SchemaChecking) -> DefinitionFileLoader {
    DefinitionFileLoader(
      fileSystem: fileSystem,
      yamlReader: yamlReader,
      technicalFieldChecker: technicalFieldChecker,
      markerBindingChecker: markerBindingChecker,
      schema: schema,
      fileReader: definitionReader,
    )
  }

  /// Every problem and warning found, sorted and without repeats (chapter 09 §27.1). A problem
  /// makes the workspace INVALID, and the warnings are not part of what it reports.
  private func warnings(of diagnostics: [Diagnostic]) throws(WorkspaceLoadingError)
    -> [Diagnostic]
  {
    let all = diagnostics.inReportOrder
    let errors = all.filter { diagnostic in
      diagnostic.severity == .error
    }

    guard errors.isEmpty else {
      throw .invalid(problems: errors.map(\.description))
    }

    return all
  }
}
