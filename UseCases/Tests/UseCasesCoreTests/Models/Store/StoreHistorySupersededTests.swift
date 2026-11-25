import Testing
@testable import UseCasesCore

/// The prune rule (chapter 12 §31) over a table of run shapes, and the promise behind it: taking
/// the superseded runs away changes no route's judgement for the workspace as it is now, wherever
/// its code is.
struct StoreHistorySupersededTests {
  static let card = UseCaseIdentifier.sample("shop.pay.card")
  static let wallet = UseCaseIdentifier.sample("shop.pay.wallet")
  static let tests = RouteIdentifier.sample("unit-tests")
  static let other = RouteIdentifier.sample("try-it")
  static let first = RouteFingerprint.sample("a")
  static let second = RouteFingerprint.sample("b")
  private static let unseen = RouteFingerprint.sample("f")

  /// A run shape: the runs, in any order, where the code is now (by default the fingerprint of the
  /// newest run that says anything about a route), and the run numbers the rule supersedes.
  struct Shape: CustomTestStringConvertible, Sendable {
    let name: String
    let runs: [StoredRun]
    let superseded: [Int]
    var now: [UseCaseIdentifier: RouteFingerprint] = [:]

    /// The routes the workspace has now; the history of a route taken out is inert.
    var routes: [RouteIdentifier] = [
      StoreHistorySupersededTests.tests,
      StoreHistorySupersededTests.other,
    ]

    var testDescription: String {
      name
    }
  }

  static func result(
    _ useCase: UseCaseIdentifier,
    _ fingerprint: RouteFingerprint,
    route: RouteIdentifier = tests,
  ) -> StoredResult {
    StoredResult(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
      verdict: .pass,
      detail: nil,
    )
  }

  static func reason(
    _ useCase: UseCaseIdentifier,
    _ fingerprint: RouteFingerprint,
  ) -> RunDiagnostic {
    RunDiagnostic.sample(
      "its test didn't run",
      useCase,
      tests,
      fingerprint,
    )
  }

  /// Every route the shapes name, at the fingerprint the code is at now.
  private static func routesNow(
    in history: StoreHistory,
    overriding now: [UseCaseIdentifier: RouteFingerprint],
    routes: [RouteIdentifier],
  ) -> [RouteAtFingerprint] {
    [card, wallet].flatMap { useCase in
      routes.compactMap { route in
        let fingerprint = now[useCase] ?? newestFingerprint(
          of: useCase,
          route: route,
          in: history,
        )

        return fingerprint.map { fingerprint in
          RouteAtFingerprint(
            useCase: useCase,
            route: route,
            fingerprint: fingerprint,
          )
        }
      }
    }
  }

  /// A history before and after its superseded runs are taken away.
  struct Pruning {
    let history: StoreHistory
    let pruned: StoreHistory
    let superseded: [RunIdentifier]
  }

  private static func pruned(
    _ runs: [StoredRun],
    at routes: [RouteAtFingerprint],
  ) -> Pruning {
    let history = StoreHistory(
      runs: runs,
      unfinishedRuns: [],
    )
    let superseded = history.supersededRuns(keeping: history.runsInUse(at: routes))
    let removed = Set(superseded)
    let pruned = StoreHistory(
      runs: runs.filter { run in
        !removed.contains(run.identifier)
      },
      unfinishedRuns: [],
    )

    return Pruning(
      history: history,
      pruned: pruned,
      superseded: superseded,
    )
  }

  @Test(arguments: shapes)
  func `the rule supersedes exactly the runs said again that status does not use now`(
    shape: Shape,
  ) {
    let history = StoreHistory(
      runs: shape.runs,
      unfinishedRuns: [],
    )
    let routes = Self.routesNow(
      in: history,
      overriding: shape.now,
      routes: shape.routes,
    )

    #expect(
      Self.pruned(shape.runs, at: routes).superseded == shape.superseded.map(RunIdentifier.sample),
    )
  }

  /// Wherever the code is, as long as it stays there: at every fingerprint any run has seen, and
  /// at one none has.
  @Test(arguments: shapes)
  func `taking the superseded runs away changes no route's judgement now`(shape: Shape) {
    let fingerprints = Set(shape.runs.flatMap { run in
      run.results.map(\.fingerprint) + (run.manifest?.diagnostics ?? []).compactMap(\.fingerprint)
    }).union([Self.unseen])

    for fingerprint in fingerprints {
      let routes = [Self.card, Self.wallet].flatMap { useCase in
        shape.routes.map { route in
          RouteAtFingerprint(
            useCase: useCase,
            route: route,
            fingerprint: fingerprint,
          )
        }
      }
      let outcome = Self.pruned(shape.runs, at: routes)

      for now in routes {
        #expect(
          outcome.pruned.judgement(
            useCase: now.useCase,
            route: now.route,
            fingerprint: now.fingerprint,
          ) == outcome.history.judgement(
            useCase: now.useCase,
            route: now.route,
            fingerprint: now.fingerprint,
          ),
          "\(now.useCase) \(now.route) at \(now.fingerprint)",
        )
      }
    }
  }

  @Test
  func `a run that never finished is never superseded and never supersedes`() {
    let history = StoreHistory(
      runs: [.sample(1, [Self.result(Self.card, Self.first)])],
      unfinishedRuns: [UnfinishedRun(identifier: .sample(2))],
    )

    #expect(history.supersededRuns().isEmpty)
  }

  private static func newestFingerprint(
    of useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    in history: StoreHistory,
  ) -> RouteFingerprint? {
    for run in history.runs.reversed() {
      let found = run.results.first { result in
        result.useCase == useCase && result.route == route
      }

      if let found {
        return found.fingerprint
      }

      let reason = run.manifest?.diagnostics.first { diagnostic in
        diagnostic.useCase == useCase && diagnostic.route == route
      }

      if let reason {
        return reason.fingerprint
      }
    }

    return nil
  }
}
