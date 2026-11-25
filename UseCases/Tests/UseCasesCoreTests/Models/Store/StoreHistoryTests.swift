import Testing
@testable import UseCasesCore

struct StoreHistoryTests {
  let useCase = UseCaseIdentifier.sample("shop.login.authenticate")
  let route = RouteIdentifier.sample("unit-tests")
  let current = RouteFingerprint.sample("a")
  let old = RouteFingerprint.sample("b")

  @Test
  func `the newest sealed result with the current fingerprint applies`() {
    let history = StoreHistory(
      runs: [
        run(1, [result(.pass, current)]),
        run(3, [result(.fail, current)]),
        run(2, [result(.pass, current)]),
      ],
      unfinishedRuns: [],
    )

    let applied = history.latestResult(useCase: useCase, route: route, fingerprint: current)

    #expect(applied?.run == RunIdentifier.sample(3))
    #expect(applied?.result.verdict == .fail)
  }

  @Test
  func `a later run for another fingerprint does not supersede a matching result`() {
    let history = StoreHistory(
      runs: [
        run(1, [result(.pass, current)]),
        run(2, [result(.fail, old)]),
      ],
      unfinishedRuns: [],
    )

    let applied = history.latestResult(useCase: useCase, route: route, fingerprint: current)
    let newest = history.latestResult(useCase: useCase, route: route)

    #expect(applied?.run == RunIdentifier.sample(1))
    #expect(newest?.run == RunIdentifier.sample(2))
  }

  @Test
  func `with no match there is still a newest result to say what the route changed since`() {
    let history = StoreHistory(
      runs: [run(1, [result(.pass, old)]), run(4, [result(.pass, old)])],
      unfinishedRuns: [],
    )

    #expect(history.latestResult(useCase: useCase, route: route, fingerprint: current) == nil)
    #expect(history.latestResult(useCase: useCase, route: route)?.run == RunIdentifier.sample(4))
  }

  @Test
  func `a fingerprint of another format never matches but is history`() {
    let future = RouteFingerprint.sample(text: "uc-route-v2-blake3:abc")
    let history = StoreHistory(
      runs: [run(1, [result(.pass, future)])],
      unfinishedRuns: [],
    )

    #expect(history.latestResult(useCase: useCase, route: route, fingerprint: current) == nil)
    #expect(history.latestResult(useCase: useCase, route: route) != nil)
  }

  @Test
  func `another route or use case has its own history`() {
    let history = StoreHistory(
      runs: [run(1, [result(.pass, current)])],
      unfinishedRuns: [],
    )

    #expect(history.results(useCase: useCase, route: RouteIdentifier.sample("other")).isEmpty)
    #expect(history.results(useCase: UseCaseIdentifier.sample("other"), route: route).isEmpty)
  }

  @Test
  func `a route's history is oldest first`() {
    let history = StoreHistory(
      runs: [run(5, [result(.fail, current)]), run(2, [result(.pass, old)])],
      unfinishedRuns: [],
    )

    #expect(history.results(useCase: useCase, route: route).map(\.run) == [
      RunIdentifier.sample(2),
      RunIdentifier.sample(5),
    ])
  }

  @Test
  func `runs and unfinished runs are put in ascending run id`() {
    let history = StoreHistory(
      runs: [run(9, []), run(2, [])],
      unfinishedRuns: [
        UnfinishedRun(identifier: RunIdentifier.sample(8)),
        UnfinishedRun(identifier: RunIdentifier.sample(3)),
      ],
    )

    #expect(history.runs.map(\.identifier) == [RunIdentifier.sample(2), RunIdentifier.sample(9)])
    #expect(history.unfinishedRuns.map(\.identifier) == [
      RunIdentifier.sample(3),
      RunIdentifier.sample(8),
    ])
  }

  @Test
  func `the newest diagnostic for the route at the fingerprint explains the missing verdict`() {
    let wording = RunDiagnostic.sample("its test didn't run", useCase, route, current)
    let other = RunDiagnostic.sample("code changed during the run", useCase, route, current)
    let elsewhere = RunDiagnostic.sample("not linked", useCase, route, old)
    let history = StoreHistory(
      runs: [
        run(1, [], diagnostics: [wording]),
        run(2, [], diagnostics: [elsewhere]),
        run(3, [], diagnostics: [other, wording]),
        run(4, [], diagnostics: []),
      ],
      unfinishedRuns: [],
    )

    let found = history.latestDiagnostic(useCase: useCase, route: route, fingerprint: current)

    #expect(found?.run == RunIdentifier.sample(3))
    #expect(found?.diagnostic.problem == "code changed during the run")
    #expect(history.latestDiagnostic(useCase: useCase, route: route, fingerprint: old)?.run
      == RunIdentifier.sample(2))
  }

  @Test
  func `a run read through its envelope has no diagnostics`() {
    let history = StoreHistory(
      runs: [run(1, [], diagnostics: nil)],
      unfinishedRuns: [],
    )

    #expect(history.latestDiagnostic(useCase: useCase, route: route, fingerprint: current) == nil)
  }

  private func result(
    _ verdict: Verdict,
    _ fingerprint: RouteFingerprint,
  ) -> StoredResult {
    StoredResult(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
      verdict: verdict,
      detail: nil,
    )
  }

  private func run(
    _ number: Int,
    _ results: [StoredResult],
    diagnostics: [RunDiagnostic]? = [],
  ) -> StoredRun {
    StoredRun.sample(
      number,
      results,
      diagnostics: diagnostics,
    )
  }
}
