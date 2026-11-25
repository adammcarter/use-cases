extension WorkspaceDiscoverer {
  /// The `.yml` and `.yaml` files a scope owns, sorted by path. A `use_cases_dir` that is not
  /// there reads as empty (chapter 04); one that cannot be searched is reported. A `use_cases_dir`
  /// is read whole: nothing inside it is skipped without a diagnostic.
  func discoverDefinitions(
    ofScopeAt scope: WorkspacePath,
    settings: ScopeSettings,
    context: DiscoveryContext,
    diagnostics: inout [Diagnostic],
  ) -> [WorkspacePath] {
    guard
      let folder = locateUseCasesDirectory(
        ofScopeAt: scope,
        settings: settings,
        context: context,
        diagnostics: &diagnostics,
      )
    else {
      return []
    }

    var found: [WorkspacePath] = []
    var pending = [folder]

    while let directory = pending.popLast() {
      let entries: [FileEntry]

      do {
        entries = try fileSystem.entries(in: context.url(for: directory))
      } catch {
        diagnostics.append(.unreadableDirectory(directory, because: error))
        continue
      }

      for entry in entries {
        switch outcome(
          of: entry,
          in: directory,
          definitions: folder,
          context: context,
        ) {
        case let .descend(path):
          pending.append(path)
        case let .definition(path):
          found.append(path)
        case let .refuse(diagnostic):
          diagnostics.append(diagnostic)
        case .skip:
          break
        }
      }
    }

    return found.sorted()
  }

  /// What an entry below a `use_cases_dir` is: a folder to search, a definition, a problem, or
  /// nothing to do with definitions. Nothing is passed over without saying so: not a name no
  /// path can spell, not a path an exclusion covers.
  private func outcome(
    of entry: FileEntry,
    in directory: WorkspacePath,
    definitions: WorkspacePath,
    context: DiscoveryContext,
  ) -> DefinitionEntryOutcome {
    let path: WorkspacePath

    do {
      path = try directory.appending(entry: entry)
    } catch {
      return .refuse(.unspellableNameInDefinitions(entry.displayName, in: directory))
    }

    if let match = context.exclusion(covering: path) {
      return .refuse(
        .exclusionInsideDefinitions(
          path,
          definitions: definitions,
          by: match,
        ),
      )
    }

    switch entry.kind {
    case .directory:
      return context.claimedDirectories.contains(path) ? .skip : .descend(path)
    case .symlink:
      return .refuse(.symlinkInDefinitions(path))
    case .file:
      switch DefinitionFileName(entry.name) {
      case .definition:
        return .definition(path)
      case let .wrongCase(renamed):
        return .refuse(.uppercaseEnding(path, renamed: renamed))
      case .notYAML:
        return .skip
      }
    case .other:
      // Never opened: a pipe named like a definition would block the read forever.
      let isYAML = DefinitionFileName(entry.name) != .notYAML
      return isYAML ? .refuse(.notAFileInDefinitions(path)) : .skip
    }
  }

  /// The scope's `use_cases_dir` when there is a folder to search; `nil` when there is none to
  /// search: it is missing (an empty one), or it is INVALID and a diagnostic says why.
  private func locateUseCasesDirectory(
    ofScopeAt scope: WorkspacePath,
    settings: ScopeSettings,
    context: DiscoveryContext,
    diagnostics: inout [Diagnostic],
  ) -> WorkspacePath? {
    let configuration = scope.appending(literal: DiscoveredScope.configurationFileName)
    let folder = scope.joining(settings.useCasesDirectory)

    if folder == scope {
      diagnostics.append(.definitionsHoldConfiguration(configuration, definitions: folder))
      return nil
    }

    // Another scope's own folder is that scope's, and reported by the ownership check.
    if context.claimedDirectories.contains(folder) {
      return nil
    }

    if let match = context.exclusion(covering: folder) {
      diagnostics.append(
        .definitionsExcluded(
          configuration,
          definitions: folder,
          by: match,
        ),
      )
      return nil
    }

    return resolveFolder(
      settings.useCasesDirectory.segments,
      below: scope,
      namedAs: folder,
      context: context,
      diagnostics: &diagnostics,
    ) ? folder : nil
  }

  /// Follows the segments down from the scope's folder, finding each one by listing its parent
  /// and requiring an entry with exactly that spelling. A file system that would find the name
  /// by ignoring case or Unicode form is not asked (chapter 09 §19).
  private func resolveFolder(
    _ segments: [String],
    below scope: WorkspacePath,
    namedAs folder: WorkspacePath,
    context: DiscoveryContext,
    diagnostics: inout [Diagnostic],
  ) -> Bool {
    let configuration = scope.appending(literal: DiscoveredScope.configurationFileName)
    var current = scope

    for segment in segments {
      let entries: [FileEntry]

      do {
        entries = try fileSystem.entries(in: context.url(for: current))
      } catch {
        diagnostics.append(.unreadableDirectory(current, because: error))
        return false
      }

      guard
        let entry = entries.first(where: { entry in
          entry.name.isExactlyEqual(to: segment)
        })
      else {
        if let problem = spellingProblem(
          segment,
          in: entries,
          below: current,
          folder: folder,
          configuration: configuration,
        ) {
          diagnostics.append(problem)
        }

        return false
      }

      current = current.appending(literal: segment)

      switch entry.kind {
      case .directory:
        continue
      case .symlink:
        diagnostics.append(
          .definitionsBehindSymlink(
            configuration,
            definitions: folder,
            link: current,
          ),
        )
        return false
      case .file, .other:
        diagnostics.append(.definitionsNotAFolder(configuration, definitions: folder))
        return false
      }
    }

    return true
  }

  /// What to say about a segment of a `use_cases_dir` that is not found as written: if something
  /// is there that matches it when case or Unicode form is ignored, the message names it as it
  /// is on disk, from the workspace root, so a wrong segment part-way along is named with the
  /// folders above it. If nothing is there, the folder is missing, which reads as an empty one.
  private func spellingProblem(
    _ segment: String,
    in entries: [FileEntry],
    below current: WorkspacePath,
    folder: WorkspacePath,
    configuration: WorkspacePath,
  ) -> Diagnostic? {
    let lookalikes = entries.map(\.name).filter { name in
      name.isLooselyEqual(to: segment)
    }.map { name in
      (try? current.appending(component: name))?.text ?? name
    }

    guard !lookalikes.isEmpty else {
      return nil
    }

    return .definitionsSpelledDifferently(
      configuration,
      definitions: folder,
      written: segment,
      onDisk: lookalikes,
    )
  }
}
