extension StoreHistory {
  /// The state of a route at its current fingerprint (chapter 12 §27, chapter 15).
  ///
  /// A result for exactly this fingerprint decides it: the one from the greatest run id. With none,
  /// the route is stale when it has any older result and unverified when it has none; the newest
  /// run diagnostic for this fingerprint says why no verdict came, and otherwise a stale route
  /// names the run it has changed since.
  func judgement(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    fingerprint: RouteFingerprint,
  ) -> RouteJudgement {
    if let decided = latestResult(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
    ) {
      return RouteJudgement(
        status: VerificationStatus(verdict: decided.result.verdict),
        explanation: .decided(
          run: decided.run.text,
          via: decided.result.detail?.origin.sources ?? [],
        ),
      )
    }

    let newest = latestResult(
      useCase: useCase,
      route: route,
    )
    let status: VerificationStatus = newest == nil ? .unverified : .stale

    if let withheld = latestDiagnostic(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
    ) {
      return RouteJudgement(
        status: status,
        explanation: .withheld(
          problem: withheld.diagnostic.problem,
          run: withheld.run.text,
        ),
      )
    }

    guard let newest else {
      return RouteJudgement(
        status: status,
        explanation: .noVerdictYet,
      )
    }

    return RouteJudgement(
      status: status,
      explanation: .changedSince(run: newest.run.text),
    )
  }
}
