import Testing
@testable import UseCasesCore

struct VerdictRecorderPlanTests {
  private func multiple() throws -> RecorderFixture {
    try RecorderFixture(definitions: FreshnessSamples.multipleUseCases())
  }

  @Test
  func `a route of a READY use case is planned with the fingerprint it has now`() throws {
    let fixture = try RecorderFixture()

    let plan = try fixture.plan("app.toggle", "unit-tests", "fail")

    #expect(plan.useCase == "app.toggle")
    #expect(plan.route == "unit-tests")
    #expect(plan.status == "fail")
    #expect(try plan.fingerprint == fixture.freshness.fingerprint(of: "unit-tests"))
  }

  @Test
  func `the two routes of a use case have their own fingerprints`() throws {
    let fixture = try RecorderFixture()

    let manual = try fixture.plan("app.toggle", "manual")
    let unit = try fixture.plan("app.toggle", "unit-tests")

    #expect(manual.fingerprint != unit.fingerprint)
  }

  @Test
  func `planning writes nothing`() throws {
    let fixture = try RecorderFixture()

    _ = try fixture.plan("app.toggle", "manual")

    #expect(!fixture.hasStore)
  }

  @Test(arguments: ["pass", "fail", "incomplete", "error"])
  func `every status the store keeps is taken`(status: String) throws {
    let fixture = try RecorderFixture()

    #expect(try fixture.plan("app.toggle", "manual", status).status == status)
  }

  @Test(arguments: ["verified", "PASS", "", "passed", "skip"])
  func `a status the store does not keep is a usage error`(status: String) throws {
    let fixture = try RecorderFixture()

    #expect(throws: RecordingError.unknownStatus(status)) {
      try fixture.plan("app.toggle", "manual", status)
    }
  }

  @Test
  func `the status is judged before the use case is looked for`() throws {
    let fixture = try RecorderFixture()

    #expect(throws: RecordingError.unknownStatus("maybe")) {
      try fixture.plan("app.nosuch", "manual", "maybe")
    }
  }

  @Test
  func `the start of one id names that use case`() throws {
    let fixture = try multiple()

    let plan = try fixture.plan("app.al", "unit")

    #expect(plan.useCase == "app.alpha")
  }

  @Test
  func `an id that starts several is ambiguous and lists them in byte order`() throws {
    let fixture = try multiple()

    #expect(
      throws: RecordingError.ambiguousUseCase(
        "app.",
        matching: ["app.alpha", "app.beta", "app.gamma"],
      ),
    ) {
      try fixture.plan("app.", "unit")
    }
  }

  @Test
  func `an exact id wins over a longer id it starts`() throws {
    let longer = FreshnessSamples.definitions()
      .replacingOccurrences(
        of: "  - id: toggle\n",
        with: "  - id: toggle-two\n",
      )
    let fixture = try RecorderFixture()
    try fixture.freshness.write("use-cases/two.yml", longer)

    let plan = try fixture.plan("app.toggle", "manual")

    #expect(plan.useCase == "app.toggle")
  }

  @Test
  func `a use case that is not there is a usage error`() throws {
    let fixture = try RecorderFixture()

    #expect(throws: RecordingError.noUseCase("app.nosuch")) {
      try fixture.plan("app.nosuch", "manual")
    }
  }

  @Test
  func `a route that is not there is a usage error that names both`() throws {
    let fixture = try RecorderFixture()

    #expect(throws: RecordingError.noRoute(useCase: "app.toggle", route: "nope")) {
      try fixture.plan("app.toggle", "nope")
    }
    #expect(RecordingError.noRoute(useCase: "app.toggle", route: "nope")
      .message == "no route app.toggle / nope")
  }

  @Test
  func `the start of one route id names that route`() throws {
    let fixture = try RecorderFixture()

    #expect(try fixture.plan("app.toggle", "uni").route == "unit-tests")
  }

  @Test
  func `a DRAFT use case cannot be recorded against, and says what it lacks`() throws {
    let fixture = try RecorderFixture(
      definitions: FreshnessSamples.definitions(isReady: false),
    )

    #expect(throws: RecordingError.draft(useCase: "app.toggle", missing: ["value_tier"])) {
      try fixture.plan("app.toggle", "manual")
    }
  }

  @Test
  func `a route a DRAFT does not have is reported as missing before the draft is`() throws {
    let fixture = try RecorderFixture(
      definitions: FreshnessSamples.definitions(isReady: false),
    )

    #expect(throws: RecordingError.noRoute(useCase: "app.toggle", route: "nope")) {
      try fixture.plan("app.toggle", "nope")
    }
  }

  @Test
  func `a workspace made INVALID by a resource is refused with the problems`() throws {
    let fixture = try RecorderFixture(
      definitions: FreshnessSamples.definitions(
        resources: [FreshnessSamples.file("fixtures/gone.json")],
      ),
    )

    let error = #expect(throws: RecordingError.self) {
      try fixture.plan("app.toggle", "unit-tests")
    }

    guard case let .invalidWorkspace(problems)? = error else {
      Issue.record("expected an invalid workspace, got \(String(describing: error))")
      return
    }

    #expect(
      problems.contains { problem in
        problem.contains("fixtures/gone.json")
      },
    )
  }
}
