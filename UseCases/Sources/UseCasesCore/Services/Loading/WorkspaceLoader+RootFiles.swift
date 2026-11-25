extension WorkspaceLoader {
  /// What the two optional root files, the bridge settings and the groups, bring to a load.
  struct RootFiles {
    let bridge: BridgeSettings?
    let groups: [UseCaseGroup]

    /// The problems of the bridge settings, which make the workspace INVALID.
    let errors: [Diagnostic]

    /// The problems of the groups file. They make the workspace INVALID too, but wait for the
    /// stage that resolves links, to be raised with its problems (chapter 09 §27, §34).
    let groupProblems: [Diagnostic]

    /// What either file does that is worth saying, in report order.
    let warnings: [Diagnostic]

    /// The problems to raise now: those of the bridge settings, and the groups' too when the load
    /// fails anyway. Otherwise the groups' wait for the links (chapter 09 §27, §34).
    ///
    /// - Parameter earlier: Everything found before the root files.
    func problemsToRaise(given earlier: [Diagnostic]) -> [Diagnostic] {
      guard (earlier + errors).containsError else {
        return errors
      }

      return errors + groupProblems
    }
  }

  /// Loads the bridge settings and then the groups (chapter 09 §21, §22).
  ///
  /// - Parameter diagnostics: Everything found so far, to which the problems to raise now are
  ///   added. Groups are resolved against every use case, so a use case file that could not be
  ///   read leaves the set unknown, and the groups file is then checked for its structure only.
  func loadRootFiles(
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
    useCases: [LoadedUseCase],
    schemas: Schemas,
    diagnostics: inout [Diagnostic],
  ) -> RootFiles {
    let bridge = bridgeLoader(checkingWith: schemas.bridge).load(
      in: root,
      scopes: scopes,
    )
    let groups = groupsLoader(checkingWith: schemas.groups).load(
      in: root,
      scopes: scopes,
      among: diagnostics.containsError ? .uncertain : .all(useCases.map(\.identifier)),
    )
    let found = (bridge.diagnostics + groups.diagnostics).inReportOrder
    let heldProblems = groups.diagnostics.filter { diagnostic in
      diagnostic.severity == .error
    }.inReportOrder

    let files = RootFiles(
      bridge: bridge.settings,
      groups: groups.groups,
      errors: bridge.diagnostics.filter { diagnostic in
        diagnostic.severity == .error
      },
      groupProblems: heldProblems,
      warnings: found.filter { diagnostic in
        diagnostic.severity == .warning
      },
    )

    diagnostics += files.problemsToRaise(given: diagnostics)

    return files
  }

  private func groupsLoader(checkingWith schema: any SchemaChecking) -> GroupsLoader {
    GroupsLoader(
      fileSystem: fileSystem,
      yamlReader: yamlReader,
      schema: schema,
      resolver: GroupResolver(),
      locator: OwnedFileLocator(fileSystem: fileSystem),
    )
  }

  private func bridgeLoader(checkingWith schema: any SchemaChecking) -> BridgeSettingsLoader {
    BridgeSettingsLoader(
      fileSystem: fileSystem,
      yamlReader: yamlReader,
      schema: schema,
      checker: BridgeSettingsChecker(
        fileSystem: fileSystem,
        pathFinder: ExactPathFinder(fileSystem: fileSystem),
      ),
      advisor: BridgeSettingsAdvisor(),
      locator: OwnedFileLocator(fileSystem: fileSystem),
    )
  }
}
