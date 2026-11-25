extension RouteFingerprintComputer {
  /// Resolves the resources of every route of every use case, drafts included (chapter 09
  /// §20.2). The code scan's files are listed once, and only when some route has a glob.
  func resolveResources(
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
  ) -> ResourceResolution {
    let scanned = hasGlob(in: run.workspace)
      ? scanLister.files(in: run.workspace, excluding: run.context)
      : ScannedFiles.empty
    var resolution = ResourceResolution(diagnostics: scanned.diagnostics)

    for useCase in run.workspace.useCases {
      for route in useCase.definition.routes {
        let key = RouteKey(
          useCase: useCase.identifier,
          route: route.identifier,
        )
        let resolved = resourceResolver.resolve(
          route.resources,
          among: scanned.files,
          in: run.context,
          listings: &caches.listings,
        )

        resolution.byRoute[key] = resolved
        resolution.warnings += excludedContentWarnings(
          of: route,
          resolved: resolved,
          key: key,
          context: run.context,
        )
        resolution.diagnostics += resolved.problems.map { problem in
          .resourceProblem(problem, of: key, definedIn: useCase.file)
        }
      }
    }

    return resolution
  }

  /// The content of a route's resource files, sorted by path. A file several routes name is read
  /// and hashed once (chapter 11 §74).
  func resourceContributions(
    of resolved: ResolvedResources,
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
    definedIn definition: WorkspacePath,
    route: RouteKey,
  ) -> ResourceContributions {
    var found = ResourceContributions()

    guard resolved.problems.isEmpty else {
      return found
    }

    for file in resolved.files.sorted() {
      if let known = caches.references[file] {
        found.contributions.append(ResourceContribution(file: file, content: known))
        continue
      }

      do {
        let reference = try reference(
          of: file,
          in: run,
          caches: &caches,
        )

        caches.references[file] = reference
        found.contributions.append(ResourceContribution(file: file, content: reference))
      } catch {
        found.diagnostics.append(
          .resourceProblem(
            .content(file, error),
            of: route,
            definedIn: definition,
          ),
        )
      }
    }

    return found
  }

  /// The reference of a resource file. A file that is held already, or that a link has to hold,
  /// is referenced from what is held; any other is read a chunk at a time, as big as it may be,
  /// and its digest is kept for the stamp.
  private func reference(
    of file: WorkspacePath,
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
  ) throws(FileContentError) -> ContentReference {
    guard caches.bytes[file] == nil, !run.linkedFiles.contains(file) else {
      return try run.referencer.reference(
        of: caches.bytes(
          of: file,
          using: contentReader,
          in: run.context,
        ),
      )
    }

    let context = run.context
    let streamed = try run.referencer.reference(
      streaming: { () throws(FileContentError) in
        try contentReader.chunks(
          of: file,
          in: context,
        )
      },
    )

    caches.streamedDigests[file] = streamed.digest

    return streamed.reference
  }

  /// An explicit file that resolved and lies in excluded content warns, as a binding does. A
  /// glob cannot reach such a file, so only explicit paths are asked.
  private func excludedContentWarnings(
    of route: ValidationRoute,
    resolved: ResolvedResources,
    key: RouteKey,
    context: DiscoveryContext,
  ) -> [Diagnostic] {
    route.resources.compactMap { resource in
      guard
        case let .file(path) = resource,
        resolved.files.contains(path),
        let exclusion = context.exclusion(covering: path)
      else {
        return nil
      }

      return .resourceIntoExcludedContent(path, of: key, because: exclusion)
    }
  }

  private func hasGlob(in workspace: LoadedWorkspace) -> Bool {
    workspace.useCases.contains { useCase in
      useCase.definition.routes.contains { route in
        route.resources.contains { resource in
          if case .glob = resource {
            return true
          }

          return false
        }
      }
    }
  }
}
