import Foundation

extension WorkspaceLoader {
  /// The checkers for the two schemas a load needs, loaded once.
  struct Schemas {
    let workspace: any SchemaChecking
    let useCases: any SchemaChecking
    let bridge: any SchemaChecking
    let groups: any SchemaChecking
  }

  func loadSchemas() throws(WorkspaceLoadingError) -> Schemas {
    do {
      return try Schemas(
        workspace: schemaLoader.loadChecker(for: .workspace),
        useCases: schemaLoader.loadChecker(for: .useCases),
        bridge: schemaLoader.loadChecker(for: .bridge),
        groups: schemaLoader.loadChecker(for: .useCaseGroups),
      )
    } catch {
      throw .schemasUnavailable(message: "the schemas in this build cannot be loaded: \(error)")
    }
  }

  /// The checked root: found by walking up, or the folder named.
  func findRoot(
    from start: WorkspaceStart,
    settingsLoader: any ScopeSettingsLoading,
  ) throws(WorkspaceLoadingError) -> WorkspaceRoot {
    let finder = RootFinder(
      fileSystem: fileSystem,
      settingsLoader: settingsLoader,
    )

    do {
      switch start {
      case let .searchingUpward(folder):
        return try finder.findRoot(from: folder)
      case let .workspace(folder):
        return try finder.requireRoot(at: folder)
      }
    } catch {
      throw refusal(
        for: error,
        start: start,
      )
    }
  }

  /// A refusal to name a root. A `use-cases.yml` that decides the root and cannot be used lists
  /// every problem in it, sorted. When the root folder is named, its file is named relative to
  /// it; when the folder was only searched for, there is no workspace to be relative to yet, so
  /// the lines name the file in full.
  private func refusal(
    for error: RootFindingError,
    start: WorkspaceStart,
  ) -> WorkspaceLoadingError {
    if case let .noConfiguration(folder) = error {
      return .noWorkspace(message: noConfigurationMessage(for: folder))
    }

    guard case let .unreadableConfiguration(folder, reason) = error else {
      return .noWorkspace(message: error.description)
    }

    let relative = Diagnostic.configuration(
      .root.appending(literal: DiscoveredScope.configurationFileName),
      refused: reason,
    ).sorted()

    guard case .searchingUpward = start else {
      return .invalid(problems: relative.map(\.description))
    }

    let file = folder.appendingPathComponent(DiscoveredScope.configurationFileName).path

    return .invalid(
      problems: relative.map { problem in
        file + problem.description.dropFirst(problem.file.text.count)
      },
    )
  }

  /// A folder with no `use-cases.yml`. If it holds a file that is one only when case or Unicode
  /// form is ignored, the message names the spelling on disk (chapter 09 §11.1).
  private func noConfigurationMessage(for folder: URL) -> String {
    let plain = RootFindingError.noConfiguration(folder).description

    let lookalikes = ((try? fileSystem.entries(in: folder)) ?? []).filter { entry in
      entry.kind != .directory
        && entry.name.isLooselyEqual(to: DiscoveredScope.configurationFileName)
    }

    guard !lookalikes.isEmpty else {
      return plain
    }

    let names = lookalikes.map(\.name).sorted { lhs, rhs in
      lhs.precedesExactly(rhs)
    }.map(\.debugDescription).joined(separator: ", ")

    return plain + "; on disk: \(names), which is not spelled use-cases.yml, case and Unicode "
      + "form included"
  }
}
