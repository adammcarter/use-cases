extension WorkspaceLoader {
  /// Every use case of every scope under its full id, scope by scope, each scope's files by path
  /// and each file's use cases as written (chapter 09 §16). Every file is read and checked; the
  /// use cases of a scope below one whose configuration could not be read are left out, since
  /// that scope's prefix is unknown and so are their ids.
  func loadUseCases(
    in scopes: [LoadedScope],
    root: WorkspaceRoot,
    uncertainBelow unreadable: [WorkspacePath],
    definitionLoader: any DefinitionFileLoading,
    diagnostics: inout [Diagnostic],
  ) -> [LoadedUseCase] {
    let byDirectory = Dictionary(
      uniqueKeysWithValues: scopes.map { scope in
        (scope.discovered.directory, scope)
      },
    )
    var useCases: [LoadedUseCase] = []

    for scope in scopes {
      let directory = scope.discovered.directory
      let knowsItsIds = !unreadable.contains { folder in
        directory.isInsideOrEqual(to: folder)
      }
      let prefixes = Self.scopePrefixes(
        of: scope,
        in: byDirectory,
      )

      for path in scope.discovered.definitionFiles {
        let file: DefinitionFile

        do {
          file = try definitionLoader.load(
            at: root.location(of: path),
            path: path,
          )
        } catch {
          switch error {
          case let .invalid(problems):
            diagnostics += problems
          }

          continue
        }

        guard knowsItsIds else {
          continue
        }

        useCases += file.useCases.map { definition in
          LoadedUseCase(
            identifier: UseCaseIdentifier(
              scopePrefixes: prefixes,
              filePrefix: file.prefix,
              localIdentifier: definition.localIdentifier,
            ),
            file: path,
            scope: directory,
            definition: definition,
          )
        }
      }
    }

    return useCases
  }

  /// A diagnostic for each use case whose full id an earlier one already has, anywhere in the
  /// workspace (chapter 09 §17). "Earlier" is by file path and then by place in the file, so the
  /// answer does not depend on the order scopes were found in.
  func duplicateDiagnostics(among useCases: [LoadedUseCase]) -> [Diagnostic] {
    let ordered = useCases.enumerated().sorted { lhs, rhs in
      guard lhs.element.file == rhs.element.file else {
        return lhs.element.file < rhs.element.file
      }

      return lhs.offset < rhs.offset
    }

    var firstSeen: [UseCaseIdentifier: LoadedUseCase] = [:]
    var diagnostics: [Diagnostic] = []

    for (_, useCase) in ordered {
      guard let first = firstSeen[useCase.identifier] else {
        firstSeen[useCase.identifier] = useCase
        continue
      }

      diagnostics.append(
        .duplicateUseCase(
          useCase.identifier,
          in: useCase.file,
          alsoIn: first.file,
        ),
      )
    }

    return diagnostics
  }

  /// The prefixes the scope's namespace is made of, the root's first. A scope without a prefix
  /// adds nothing (chapter 09 §10).
  private static func scopePrefixes(
    of scope: LoadedScope,
    in scopes: [WorkspacePath: LoadedScope],
  ) -> [Namespace] {
    var chain = [scope]
    var current = scope

    while let parent = current.discovered.parent, let above = scopes[parent] {
      chain.append(above)
      current = above
    }

    return chain.reversed().compactMap { scope in
      scope.configuration.prefix
    }
  }
}
