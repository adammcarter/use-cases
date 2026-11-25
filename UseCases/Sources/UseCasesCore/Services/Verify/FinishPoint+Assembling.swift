extension FinishPoint {
  /// Turns what the judge said into the results to store and the diagnostics of the manifest, in
  /// the order of the workspace. The guard (chapter 13 §7 step 6) looks only at a verdict, which
  /// is all it can withhold: a route with no verdict keeps its own reason, and a route that only
  /// a person can speak for (a procedure and no link) has none to give.
  func assemble(
    order: [RouteKey],
    outcomes: [RouteKey: RouteOutcome],
    guardian: Guardian,
    links: LinkResolution,
    didntRun: String,
  ) -> Judged {
    var results: [StoredResult] = []
    var diagnostics = links.warningLines.map { line in
      RunDiagnostic(
        problem: line,
        useCase: nil,
        route: nil,
        fingerprint: nil,
        files: [],
        links: [],
      )
    }

    for key in order {
      guard let outcome = outcomes[key] else {
        continue
      }

      // A route the start point did not know cannot be judged against a fingerprint (step 5).
      guard let fingerprint = guardian.started[key] else {
        diagnostics.append(guardian.unknown(key))
        continue
      }

      switch outcome {
      case let .verdict(verdict):
        if let changed = guardian.changed(key) {
          diagnostics.append(changed)
        } else {
          results.append(storedResult(of: verdict, fingerprint: fingerprint))
        }
      case .notLinked:
        diagnostics.append(explanation(Self.notLinked, of: key, at: fingerprint))
      case let .didntRun(missing):
        diagnostics.append(
          explanation(
            didntRun,
            of: key,
            at: fingerprint,
            links: missing,
          ),
        )
      }
    }

    return Judged(
      results: results,
      diagnostics: diagnostics,
    )
  }

  private func storedResult(
    of verdict: RouteVerdict,
    fingerprint: RouteFingerprint,
  ) -> StoredResult {
    StoredResult(
      useCase: verdict.key.useCase,
      route: verdict.key.route,
      fingerprint: fingerprint,
      verdict: verdict.verdict,
      detail: StoredResultDetail(
        recordedAt: clock.now().storeTimestamp,
        origin: .validations(
          verdict.via,
          links: verdict.links,
        ),
        message: nil,
        attachments: [],
      ),
    )
  }

  private func explanation(
    _ problem: String,
    of key: RouteKey,
    at fingerprint: RouteFingerprint,
    links: [String] = [],
  ) -> RunDiagnostic {
    RunDiagnostic(
      problem: problem,
      useCase: key.useCase,
      route: key.route,
      fingerprint: fingerprint,
      files: [],
      links: links,
    )
  }
}
