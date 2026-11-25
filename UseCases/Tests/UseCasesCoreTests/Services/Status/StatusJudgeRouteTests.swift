import Testing
@testable import UseCasesCore

struct StatusJudgeRouteTests {
  private let fixture: StatusFixture

  init() throws {
    fixture = try StatusFixture()
  }

  private func routes(_ useCase: UseCaseStatus) -> [String: RouteStatus] {
    Dictionary(
      uniqueKeysWithValues: useCase.routes.map { route in
        (route.identifier, route)
      },
    )
  }

  @Test
  func `in a checkout where nothing has run every route is unverified`() throws {
    let status = try fixture.status()
    let useCase = try fixture.useCase()

    #expect(!status.hasSealedRuns)
    #expect(useCase.status == .unverified)
    #expect(useCase.routes.map(\.status) == [.unverified, .unverified])
    #expect(useCase.routes.map(\.explanation) == [.noVerdictYet, .noVerdictYet])
    #expect(useCase.routes.map(\.identifier) == ["manual", "unit-tests"])
  }

  @Test
  func `a use case is verified when all its gating routes pass`() throws {
    try fixture.record("manual")
    try fixture.record("unit-tests")

    let useCase = try fixture.useCase()
    let status = try fixture.status()

    #expect(status.hasSealedRuns)
    #expect(useCase.status == .verified)
    #expect(useCase.decidingRoute?.status == .verified)
  }

  @Test
  func `the worst gating route decides the use case`() throws {
    try fixture.record("manual")
    try fixture.record("unit-tests", "fail")

    let useCase = try fixture.useCase()

    #expect(useCase.status == .failed)
    #expect(useCase.decidingRoute?.identifier == "unit-tests")
    #expect(routes(useCase)["manual"]?.status == .verified)
  }

  @Test(arguments: [
    ("fail", VerificationStatus.failed),
    ("error", VerificationStatus.error),
    ("incomplete", VerificationStatus.incomplete),
  ])
  func `each verdict gives the route its state`(
    verdict: String,
    expected: VerificationStatus,
  ) throws {
    try fixture.record("manual")
    try fixture.record("unit-tests", verdict)

    #expect(try routes(fixture.useCase())["unit-tests"]?.status == expected)
  }

  @Test
  func `a route nobody has run keeps an otherwise verified use case unverified`() throws {
    try fixture.record("manual")

    let useCase = try fixture.useCase()

    #expect(useCase.status == .unverified)
    #expect(useCase.decidingRoute?.identifier == "unit-tests")
  }

  @Test
  func `a newer verdict for the same state replaces an older one`() throws {
    try fixture.record("manual")
    try fixture.record("unit-tests", "fail")
    try fixture.record("unit-tests", "pass")

    #expect(try fixture.useCase().status == .verified)
  }

  @Test
  func `changing what a route is judged on makes it stale and names the newest run of each route`(
  ) throws {
    try fixture.record("manual")
    try fixture.record("unit-tests")
    let history = try StoreReader().readHistory(in: fixture.recording.workspace)
    let runs = history.runs.map(\.identifier.text)

    try fixture.rewrite(
      FreshnessSamples.definitions()
        .replacingOccurrences(
          of: "Readable at night.",
          with: "Readable all day.",
        ),
    )

    let useCase = try fixture.useCase()

    #expect(useCase.status == .stale)
    #expect(useCase.routes.map(\.status) == [.stale, .stale])
    #expect(useCase.routes.map(\.explanation) == [
      .changedSince(run: runs[0]),
      .changedSince(run: runs[1]),
    ])
  }

  @Test
  func `restoring the old wording makes the old verdict apply again`() throws {
    try fixture.record("manual")
    try fixture.record("unit-tests")
    try fixture.rewrite(
      FreshnessSamples.definitions()
        .replacingOccurrences(
          of: "Readable at night.",
          with: "Readable all day.",
        ),
    )
    #expect(try fixture.useCase().status == .stale)

    try fixture.rewrite(FreshnessSamples.definitions())

    #expect(try fixture.useCase().status == .verified)
  }

  @Test
  func `a changed link makes the route stale`() throws {
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#unit-tests.code", "work()"),
    )
    try fixture.record("manual")
    try fixture.record("unit-tests")
    #expect(try fixture.useCase().status == .verified)

    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#unit-tests.code", "work(differently)"),
    )

    let useCase = try fixture.useCase()

    #expect(routes(useCase)["unit-tests"]?.status == .stale)
    #expect(routes(useCase)["manual"]?.status == .verified)
  }

  @Test
  func `a recorded verdict is told as coming from record`() throws {
    try fixture.record("manual")
    let history = try StoreReader().readHistory(in: fixture.recording.workspace)
    let run = try #require(history.runs.first)

    let route = try #require(routes(fixture.useCase())["manual"])

    #expect(route.explanation == .decided(run: run.identifier.text, via: ["record"]))
  }

  @Test
  func `a route with a procedure is linked and one with nothing to reach it is not`() throws {
    let useCase = try fixture.useCase()

    #expect(routes(useCase)["manual"]?.isLinked == true)
    #expect(routes(useCase)["unit-tests"]?.isLinked == false)
  }

  @Test
  func `a validation link makes a route linked`() throws {
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#unit-tests.code", "work()"),
    )

    #expect(try routes(fixture.useCase())["unit-tests"]?.isLinked == true)
  }
}
