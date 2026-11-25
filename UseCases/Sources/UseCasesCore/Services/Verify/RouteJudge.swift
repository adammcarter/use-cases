/// The judge of chapter 07.
struct RouteJudge: RouteJudging {
  func judge(
    _ routes: [JudgedRoute],
    from sources: [SourceOutcome],
  ) -> [RouteKey: RouteOutcome] {
    let heard = Heard(sources)
    var outcomes: [RouteKey: RouteOutcome] = [:]

    for route in routes {
      if let outcome = outcome(
        of: route,
        heard: heard,
      ) {
        outcomes[route.key] = outcome
      }
    }

    return outcomes
  }

  private func outcome(
    of route: JudgedRoute,
    heard: Heard,
  ) -> RouteOutcome? {
    guard !route.linkKeys.isEmpty else {
      return route.hasProcedure ? nil : .notLinked
    }

    let links = route.linkKeys.map { key in
      LinkResult(
        key: key,
        verdict: heard.verdicts[key],
      )
    }
    let missing = links.filter { $0.verdict == nil }.map(\.key)

    if !missing.isEmpty, !links.contains(where: { $0.verdict == .fail }) {
      return .didntRun(links: missing)
    }

    guard let verdict = links.compactMap(\.verdict).reduce(nil, Self.worse) else {
      return .didntRun(links: missing)
    }

    return .verdict(
      RouteVerdict(
        key: route.key,
        verdict: verdict,
        links: links,
        via: heard.sources(speakingFor: route.linkKeys),
      ),
    )
  }

  private static func worse(
    _ current: Verdict?,
    _ next: Verdict,
  ) -> Verdict {
    guard let current else {
      return next
    }

    return current.worse(than: next)
  }
}
