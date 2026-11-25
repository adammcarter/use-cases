import Testing
@testable import UseCasesCore

struct StoreHistoryRouteJudgementTests {
  private let useCase = UseCaseIdentifier.sample("shop.login.authenticate")
  private let route = RouteIdentifier.sample("unit-tests")
  private let current = RouteFingerprint.sample("a")
  private let old = RouteFingerprint.sample("b")

  private func judgement(of history: StoreHistory) -> RouteJudgement {
    history.judgement(
      useCase: useCase,
      route: route,
      fingerprint: current,
    )
  }

  private func result(
    _ verdict: Verdict,
    _ fingerprint: RouteFingerprint,
    origin: ResultOrigin? = .recorded,
  ) -> StoredResult {
    StoredResult(
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
      verdict: verdict,
      detail: origin.map { origin in
        StoredResultDetail(
          recordedAt: StoreSamples.timestamp,
          origin: origin,
          message: nil,
          attachments: [],
        )
      },
    )
  }

  @Test
  func `a route nothing was ever recorded for is unverified with no verdict yet`() {
    let history = StoreHistory(
      runs: [],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .unverified)
    #expect(answer.explanation == .noVerdictYet)
  }

  @Test(arguments: [
    (Verdict.pass, VerificationStatus.verified),
    (Verdict.fail, VerificationStatus.failed),
    (Verdict.incomplete, VerificationStatus.incomplete),
    (Verdict.error, VerificationStatus.error),
  ])
  func `a result for the current fingerprint decides the state`(
    verdict: Verdict,
    expected: VerificationStatus,
  ) {
    let history = StoreHistory(
      runs: [.sample(7, [result(verdict, current)])],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == expected)
    #expect(answer.explanation == .decided(run: StoreFixture.identifier(7), via: ["record"]))
  }

  @Test
  func `the newest result for the current fingerprint wins`() {
    let history = StoreHistory(
      runs: [
        .sample(1, [result(.fail, current)]),
        .sample(3, [result(.pass, current)]),
        .sample(2, [result(.fail, current)]),
      ],
      unfinishedRuns: [],
    )

    #expect(judgement(of: history).status == .verified)
  }

  @Test
  func `an older pass is verified again once the old fingerprint is restored`() {
    let history = StoreHistory(
      runs: [
        .sample(1, [result(.pass, current)]),
        .sample(2, [result(.fail, old)]),
      ],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .verified)
    #expect(answer.explanation == .decided(run: StoreFixture.identifier(1), via: ["record"]))
  }

  @Test
  func `results for other fingerprints only make a route stale, naming the newest run`() {
    let history = StoreHistory(
      runs: [
        .sample(1, [result(.pass, old)]),
        .sample(4, [result(.fail, old)]),
      ],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .stale)
    #expect(answer.explanation == .changedSince(run: StoreFixture.identifier(4)))
  }

  @Test
  func `a result for another route or use case is not this route's history`() {
    let other = StoredResult(
      useCase: .sample("shop.login.other"),
      route: route,
      fingerprint: current,
      verdict: .pass,
      detail: nil,
    )
    let history = StoreHistory(
      runs: [.sample(1, [other])],
      unfinishedRuns: [],
    )

    #expect(judgement(of: history).status == .unverified)
  }

  @Test
  func `a diagnostic for the current fingerprint explains a route that has no verdict`() {
    let history = StoreHistory(
      runs: [
        .sample(
          5,
          [],
          diagnostics: [.sample("its test didn't run", useCase, route, current)],
        ),
      ],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .unverified)
    #expect(
      answer.explanation == .withheld(
        problem: "its test didn't run",
        run: StoreFixture.identifier(5),
      ),
    )
  }

  @Test
  func `a diagnostic explains a stale route too, in place of the run it changed since`() {
    let history = StoreHistory(
      runs: [
        .sample(1, [result(.pass, old)]),
        .sample(
          5,
          [],
          diagnostics: [.sample("its test didn't run", useCase, route, current)],
        ),
      ],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .stale)
    #expect(
      answer.explanation == .withheld(
        problem: "its test didn't run",
        run: StoreFixture.identifier(5),
      ),
    )
  }

  @Test
  func `a diagnostic never shows for a route a result already decides`() {
    let history = StoreHistory(
      runs: [
        .sample(1, [result(.pass, current)]),
        .sample(
          5,
          [],
          diagnostics: [.sample("its test didn't run", useCase, route, current)],
        ),
      ],
      unfinishedRuns: [],
    )

    #expect(judgement(of: history).explanation == .decided(
      run: StoreFixture.identifier(1),
      via: ["record"],
    ))
  }

  @Test
  func `a diagnostic for another fingerprint explains nothing`() {
    let history = StoreHistory(
      runs: [
        .sample(
          5,
          [],
          diagnostics: [.sample("its test didn't run", useCase, route, old)],
        ),
      ],
      unfinishedRuns: [],
    )

    #expect(judgement(of: history).explanation == .noVerdictYet)
  }

  @Test
  func `a verdict from reports names the validations that gave it`() throws {
    let validations = try ResultOrigin.validations(
      [IdentifierSegment(validating: "unit-tests"), IdentifierSegment(validating: "ui-tests")],
      links: [],
    )
    let history = StoreHistory(
      runs: [.sample(2, [result(.pass, current, origin: validations)])],
      unfinishedRuns: [],
    )

    #expect(
      judgement(of: history).explanation
        == .decided(run: StoreFixture.identifier(2), via: ["unit-tests", "ui-tests"]),
    )
  }

  @Test
  func `a verdict read through its envelope still decides, with no source`() {
    let history = StoreHistory(
      runs: [.sample(2, [result(.fail, current, origin: nil)], diagnostics: nil)],
      unfinishedRuns: [],
    )

    let answer = judgement(of: history)

    #expect(answer.status == .failed)
    #expect(answer.explanation == .decided(run: StoreFixture.identifier(2), via: []))
  }
}
