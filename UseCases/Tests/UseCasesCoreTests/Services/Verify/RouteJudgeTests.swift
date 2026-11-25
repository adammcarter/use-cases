import Testing
@testable import UseCasesCore

struct RouteJudgeTests {
  private static let keyA = "app.toggle#unit-tests.a@tests/t.swift:1"
  private static let keyB = "app.toggle#unit-tests.b@tests/t.swift:9"

  private let judge = RouteJudge()

  private func route(
    _ keys: [String],
    hasProcedure: Bool = false,
  ) -> JudgedRoute {
    JudgedRoute(
      key: RouteKey(
        useCase: .sample("app.toggle"),
        route: .sample("unit-tests"),
      ),
      linkKeys: keys,
      hasProcedure: hasProcedure,
    )
  }

  private func source(
    _ identifier: String,
    _ results: [String: Verdict],
  ) throws -> SourceOutcome {
    let id = try IdentifierSegment(validating: identifier)

    return SourceOutcome(
      source: RunSource(
        identifier: id,
        report: "reports/\(identifier)",
        transformer: "junit",
        workingDirectory: nil,
        command: nil,
        exitCode: nil,
        seconds: nil,
        error: nil,
        diagnostics: [],
      ),
      results: results.sorted { $0.key < $1.key }.map { key, verdict in
        TransformerLinkResult(
          link: key,
          status: verdict,
          tests: [],
          message: nil,
        )
      },
      unlinked: [],
      readReports: [],
      isCancelled: false,
    )
  }

  private func outcome(
    _ route: JudgedRoute,
    _ sources: [SourceOutcome],
  ) -> RouteOutcome? {
    judge.judge(
      [route],
      from: sources,
    )[route.key]
  }

  @Test(arguments: [
    ([Verdict.pass, .pass], Verdict.pass),
    ([.pass, .incomplete], .incomplete),
    ([.pass, .error], .error),
    ([.incomplete, .error], .error),
    ([.error, .fail], .fail),
    ([.fail, .pass], .fail),
  ])
  func `the worst result of the links wins: fail, error, incomplete, pass`(
    results: [Verdict],
    expected: Verdict,
  ) throws {
    let spoken = try source("unit-tests", [Self.keyA: results[0], Self.keyB: results[1]])

    guard case let .verdict(verdict)? = outcome(route([Self.keyA, Self.keyB]), [spoken]) else {
      Issue.record("no verdict")
      return
    }

    #expect(verdict.verdict == expected)
    #expect(verdict.links.map(\.verdict) == results)
    #expect(verdict.via.map(\.text) == ["unit-tests"])
  }

  @Test
  func `a link with no result and no failure gives no verdict, and names the link`() throws {
    let spoken = try source("unit-tests", [Self.keyA: .pass])

    #expect(
      outcome(route([Self.keyA, Self.keyB]), [spoken]) == .didntRun(links: [Self.keyB]),
    )
  }

  @Test
  func `a route no source spoke for did not run`() {
    #expect(
      outcome(route([Self.keyA, Self.keyB]), []) == .didntRun(links: [Self.keyA, Self.keyB]),
    )
  }

  @Test
  func `a fail beats a link that did not run, and the missing link is null`() throws {
    let spoken = try source("unit-tests", [Self.keyA: .fail])

    guard case let .verdict(verdict)? = outcome(route([Self.keyA, Self.keyB]), [spoken]) else {
      Issue.record("no verdict")
      return
    }

    #expect(verdict.verdict == .fail)
    #expect(verdict.links.map(\.verdict) == [.fail, nil])
  }

  @Test(arguments: [Verdict.error, .incomplete, .pass])
  func `anything but a fail does not beat a link that did not run`(verdict: Verdict) throws {
    let spoken = try source("unit-tests", [Self.keyA: verdict])

    #expect(
      outcome(route([Self.keyA, Self.keyB]), [spoken]) == .didntRun(links: [Self.keyB]),
    )
  }

  @Test
  func `results of several sources merge before the route is judged, the worst winning`()
    throws
  {
    let first = try source("auth-tests", [Self.keyA: .pass])
    let second = try source("session-tests", [Self.keyA: .fail, Self.keyB: .pass])

    guard case let .verdict(verdict)? = outcome(route([Self.keyA, Self.keyB]), [first, second])
    else {
      Issue.record("no verdict")
      return
    }

    #expect(verdict.verdict == .fail)
    #expect(verdict.links.map(\.verdict) == [.fail, .pass])
    #expect(verdict.via.map(\.text) == ["auth-tests", "session-tests"])
  }

  @Test
  func `links spread over sources are all heard, and only the sources that spoke are named`()
    throws
  {
    let first = try source("auth-tests", [Self.keyA: .pass])
    let second = try source("session-tests", [Self.keyB: .pass])
    let silent = try source("style", [:])

    guard case let .verdict(verdict)? = outcome(
      route([Self.keyA, Self.keyB]),
      [first, silent, second],
    )
    else {
      Issue.record("no verdict")
      return
    }

    #expect(verdict.verdict == .pass)
    #expect(verdict.via.map(\.text) == ["auth-tests", "session-tests"])
  }

  @Test
  func `a route with no validation link and no procedure is not linked`() {
    #expect(outcome(route([]), []) == .notLinked)
  }

  @Test
  func `a route with a procedure and no link has no outcome: only record speaks for it`() {
    #expect(outcome(route([], hasProcedure: true), []) == nil)
  }

  @Test
  func `every route is judged on its own, in one call`() throws {
    let other = JudgedRoute(
      key: RouteKey(
        useCase: .sample("app.toggle"),
        route: .sample("other"),
      ),
      linkKeys: [Self.keyB],
      hasProcedure: false,
    )
    let spoken = try source("unit-tests", [Self.keyA: .pass])

    let outcomes = judge.judge(
      [route([Self.keyA]), other],
      from: [spoken],
    )

    #expect(outcomes.count == 2)
    #expect(outcomes[other.key] == .didntRun(links: [Self.keyB]))
  }
}
