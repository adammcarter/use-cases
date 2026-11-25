extension StoreHistory {
  /// The state of a route at its current fingerprint (chapter 12 §27, chapter 15).
  ///
  /// A result for exactly this fingerprint decides it: the one from the greatest run id. With none,
  /// the route is stale when it has any older result and unverified when it has none; the newest
  /// run diagnostic for this fingerprint says why no verdict came, and a stale route also names the
  /// run it has changed since and what that result was (chapter 15 §4, §5).
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

    return RouteJudgement(
      status: newest == nil ? .unverified : .stale,
      explanation: explanationWithoutResult(
        useCase: useCase,
        route: route,
        fingerprint: fingerprint,
        newest: newest,
      ),
    )
  }

  /// Why a route with no result at its current fingerprint has none, given its newest result at
  /// any other fingerprint.
  private func explanationWithoutResult(
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    fingerprint: RouteFingerprint,
    newest: LocatedResult?,
  ) -> RouteExplanation {
    let withheld = latestDiagnostic(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
    )

    switch (withheld, newest) {
    case let (withheld?, newest?):
      return .withheldSinceChange(
        problem: withheld.diagnostic.problem,
        run: withheld.run.text,
        changedSince: newest.run.text,
        lastResult: newest.result.verdict.rawValue,
      )
    case let (withheld?, nil):
      return .withheld(
        problem: withheld.diagnostic.problem,
        run: withheld.run.text,
      )
    case let (nil, newest?):
      return .changedSince(
        run: newest.run.text,
        lastResult: newest.result.verdict.rawValue,
      )
    case (nil, nil):
      return .noVerdictYet
    }
  }
}
