import Foundation

extension WorkspaceInitializer {
  /// What is in `folder` (chapter 17 §3): the workspace root, a child scope, a place inside a
  /// workspace, or nothing. Only the files that decide the root are read.
  func site(of folder: URL) throws(InitError) -> InitSite {
    let configurationLoader = try configurationLoader()
    let finder = RootFinder(
      fileSystem: fileSystem,
      settingsLoader: ScopeSettingsLoader(
        fileSystem: fileSystem,
        settingsReader: ScopeSettingsReader(configurationLoader: configurationLoader),
      ),
    )

    let root: WorkspaceRoot

    do {
      root = try finder.requireRoot(at: folder)
    } catch {
      switch error {
      case .noConfiguration:
        try refuseInsideWorkspace(
          folder,
          finder: finder,
        )

        return .fresh
      case .notTheRoot:
        throw .notWorkspaceRoot(path: folder.path)
      default:
        throw .invalidWorkspace(problems: [error.description])
      }
    }

    return try .workspace(
      prefix: prefix(
        of: root,
        using: configurationLoader,
      ),
    )
  }

  /// The checkers for the workspace file, loaded when they are needed.
  private func configurationLoader() throws(InitError) -> ScopeConfigurationLoader {
    let checker: any SchemaChecking

    do {
      checker = try schemaLoader.loadChecker(for: .workspace)
    } catch {
      throw .unavailable(message: "the schemas in this build cannot be loaded: \(error)")
    }

    return ScopeConfigurationLoader(
      yamlReader: yamlReader,
      schema: checker,
      configurationReader: scopeReader,
    )
  }

  private func prefix(
    of root: WorkspaceRoot,
    using configurationLoader: ScopeConfigurationLoader,
  ) throws(InitError) -> Namespace? {
    let path = WorkspacePath.root.appending(literal: DiscoveredScope.configurationFileName)

    do {
      let text = try fileSystem.readText(
        at: root.directory.appendingPathComponent(DiscoveredScope.configurationFileName),
      )

      return try configurationLoader.load(
        fromText: text,
        at: path,
      ).prefix
    } catch {
      throw .invalidWorkspace(problems: ["\(path): \(error)"])
    }
  }

  /// A workspace above the folder makes it a place inside that workspace.
  private func refuseInsideWorkspace(
    _ folder: URL,
    finder: RootFinder,
  ) throws(InitError) {
    guard folder.path != "/" else {
      return
    }

    let root: WorkspaceRoot

    do {
      root = try finder.findRoot(from: folder.deletingLastPathComponent())
    } catch {
      switch error {
      case .noRootFound:
        return
      default:
        throw .invalidWorkspace(problems: [error.description])
      }
    }

    throw .insideWorkspace(
      folder: folder.path,
      root: root.directory.path,
    )
  }
}
