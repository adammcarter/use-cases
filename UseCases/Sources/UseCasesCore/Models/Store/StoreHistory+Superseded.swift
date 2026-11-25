extension StoreHistory {
  /// The sealed runs whose every part has been said again by a later sealed run (chapter 12
  /// §31), oldest first. Removing them all together changes no status, summary, gate answer or
  /// note while the code stays where it is now.
  ///
  /// A run is superseded when all of these hold:
  ///
  /// - a later sealed run exists;
  /// - every result in it has a result in a later sealed run for the same use case + route, at
  ///   any fingerprint;
  /// - every diagnostic in it that names a use case + route has a result or a diagnostic in a
  ///   later sealed run for the same use case + route.
  ///
  /// A run whose manifest this core does not read (a newer version, read through its envelope) is
  /// never superseded: what it explains is not known. Runs with no completion marker are not
  /// sealed and never count, either way.
  ///
  /// - Parameter inUse: Runs that are never superseded whatever the rule says: the ones status
  ///   uses for the workspace as it is now (`runsInUse(at:)`).
  func supersededRuns(keeping inUse: Set<RunIdentifier> = []) -> [RunIdentifier] {
    guard let newest = runs.last?.identifier else {
      return []
    }

    var newestResult: [RouteKey: RunIdentifier] = [:]
    var newestWord: [RouteKey: RunIdentifier] = [:]

    for run in runs {
      for result in run.results {
        let key = RouteKey(
          useCase: result.useCase,
          route: result.route,
        )
        newestResult[key] = run.identifier
        newestWord[key] = run.identifier
      }

      for key in Self.explainedRoutes(of: run) {
        newestWord[key] = run.identifier
      }
    }

    return runs.filter { run in
      guard run.identifier < newest, run.manifest != nil, !inUse.contains(run.identifier) else {
        return false
      }

      let resultsSaidAgain = run.results.allSatisfy { result in
        let key = RouteKey(
          useCase: result.useCase,
          route: result.route,
        )

        return newestResult[key].map { $0 > run.identifier } ?? false
      }
      let reasonsSaidAgain = Self.explainedRoutes(of: run).allSatisfy { key in
        newestWord[key].map { $0 > run.identifier } ?? false
      }

      return resultsSaidAgain && reasonsSaidAgain
    }.map(\.identifier)
  }

  /// Every run status reads for the routes as they are now (chapter 12 §27): the result that
  /// decides a route at its current fingerprint, or else the diagnostic that explains why it has
  /// none and the newest result it has changed since.
  func runsInUse(at routes: [RouteAtFingerprint]) -> Set<RunIdentifier> {
    var used: Set<RunIdentifier> = []

    for current in routes {
      if let decided = latestResult(
        useCase: current.useCase,
        route: current.route,
        fingerprint: current.fingerprint,
      ) {
        used.insert(decided.run)
        continue
      }

      if let reason = latestDiagnostic(
        useCase: current.useCase,
        route: current.route,
        fingerprint: current.fingerprint,
      ) {
        used.insert(reason.run)
      }

      if let newest = latestResult(
        useCase: current.useCase,
        route: current.route,
      ) {
        used.insert(newest.run)
      }
    }

    return used
  }

  /// The use case + route of every diagnostic of a run that names both: the ones that can explain
  /// a route's status.
  private static func explainedRoutes(of run: StoredRun) -> [RouteKey] {
    (run.manifest?.diagnostics ?? []).compactMap { diagnostic in
      guard let useCase = diagnostic.useCase, let route = diagnostic.route else {
        return nil
      }

      return RouteKey(
        useCase: useCase,
        route: route,
      )
    }
  }
}
