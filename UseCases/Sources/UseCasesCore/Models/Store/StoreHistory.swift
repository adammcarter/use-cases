/// Every sealed run of a store that read clean, oldest first, and the lookups status makes over
/// them (chapter 12 §27).
///
/// There is no way to hold a `StoreHistory` for a store that could not be read: the reader throws
/// instead, so a caller can never infer a route's state from damaged history.
struct StoreHistory: Equatable, Sendable {
  /// The sealed runs in ascending run id, which is allocation order (chapter 12 §8).
  let runs: [StoredRun]

  /// Runs with no completion marker, in ascending run id. They never count as evidence.
  let unfinishedRuns: [UnfinishedRun]

  private let resultsByRoute: [RouteKey: [LocatedResult]]

  /// - Parameters:
  ///   - runs: The sealed runs. They are put in ascending run id.
  ///   - unfinishedRuns: The runs with no marker. They are put in ascending run id.
  init(
    runs: [StoredRun],
    unfinishedRuns: [UnfinishedRun],
  ) {
    let ordered = runs.sorted { $0.identifier < $1.identifier }
    self.runs = ordered
    self.unfinishedRuns = unfinishedRuns.sorted { $0.identifier < $1.identifier }

    var resultsByRoute: [RouteKey: [LocatedResult]] = [:]
    for run in ordered {
      for result in run.results {
        resultsByRoute[RouteKey(useCase: result.useCase, route: result.route), default: []]
          .append(LocatedResult(run: run.identifier, result: result))
      }
    }
    self.resultsByRoute = resultsByRoute
  }

  /// Every result for a use case + route, oldest run first. This is the route's history.
  func results(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
  ) -> [LocatedResult] {
    resultsByRoute[RouteKey(useCase: useCase, route: route)] ?? []
  }

  /// The result that applies to a route at its current fingerprint: from the greatest run id
  /// among the results with this exact fingerprint. `nil` when none matches, in which case the
  /// route is `stale` if ``latestResult(useCase:route:)`` finds one and `unverified` if not.
  func latestResult(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    fingerprint: RouteFingerprint,
  ) -> LocatedResult? {
    results(
      useCase: useCase,
      route: route,
    ).last { $0.result.fingerprint == fingerprint }
  }

  /// The newest result for a use case + route at any fingerprint: the one a stale route changed
  /// since.
  func latestResult(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
  ) -> LocatedResult? {
    results(
      useCase: useCase,
      route: route,
    ).last
  }

  /// The manifest diagnostic of the newest run that explains why a route got no verdict at this
  /// fingerprint, for example "its test didn't run". It explains; it is never a result.
  func latestDiagnostic(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    fingerprint: RouteFingerprint,
  ) -> LocatedDiagnostic? {
    for run in runs.reversed() {
      let match = run.manifest?.diagnostics.first {
        $0.useCase == useCase && $0.route == route && $0.fingerprint == fingerprint
      }
      if let match {
        return LocatedDiagnostic(run: run.identifier, diagnostic: match)
      }
    }

    return nil
  }

  /// Every integrity finding of every run, oldest run first.
  var findings: [RunIntegrityFinding] {
    runs.flatMap(\.findings)
  }
}
