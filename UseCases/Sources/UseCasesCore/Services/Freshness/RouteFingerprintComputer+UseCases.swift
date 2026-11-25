extension RouteFingerprintComputer {
  /// The routes of one READY use case. The implementation links are built once and shared by
  /// every route (chapter 11 §73).
  func fingerprints(
    of useCase: LoadedUseCase,
    in run: FreshnessRun,
    links: GroupedLinks,
    resources: ResourceResolution,
    caches: inout FreshnessCaches,
  ) -> UseCaseFingerprints {
    let implementation = linkBuilder.contributions(
      of: links.implementationLinks(of: useCase.identifier),
      in: run,
      caches: &caches,
    )
    var found = UseCaseFingerprints(diagnostics: implementation.diagnostics)

    for route in useCase.definition.routes {
      let key = RouteKey(
        useCase: useCase.identifier,
        route: route.identifier,
      )
      let validation = linkBuilder.contributions(
        of: links.validationLinks(of: key),
        in: run,
        caches: &caches,
      )
      let resolved = resources.byRoute[key] ?? ResolvedResources()
      let contributed = resourceContributions(
        of: resolved,
        in: run,
        caches: &caches,
        definedIn: useCase.file,
        route: key,
      )

      found.diagnostics += validation.diagnostics + contributed.diagnostics

      guard found.diagnostics.isEmpty, resolved.problems.isEmpty else {
        continue
      }

      let input = RouteFingerprintInput(
        useCase: useCase,
        route: route,
        policy: run.policy,
        implementationLinks: implementation.contributions,
        validationLinks: validation.contributions,
        resources: contributed.contributions,
      )

      add(
        input,
        of: key,
        files: Set(
          links.implementationLinks(of: useCase.identifier).map(\.path)
            + links.validationLinks(of: key).map(\.path),
        ).union(resolved.files),
        definedIn: useCase.file,
        to: &found,
      )
    }

    return found
  }

  private func add(
    _ input: RouteFingerprintInput,
    of key: RouteKey,
    files: Set<WorkspacePath>,
    definedIn definition: WorkspacePath,
    to found: inout UseCaseFingerprints,
  ) {
    do {
      let fingerprint = try fingerprinter.fingerprint(of: input)

      found.routes.append(
        LiveRouteFingerprint(
          useCase: key.useCase.text,
          route: key.route.text,
          fingerprint: fingerprint,
          files: files.sorted().map(\.text),
        ),
      )
    } catch {
      found.diagnostics.append(
        .routeNotFingerprintable(
          key,
          because: error,
          definedIn: definition,
        ),
      )
    }
  }
}
