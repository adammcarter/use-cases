import Testing
@testable import UseCasesCore

struct StatusJudgeUseCaseTests {
  /// `app.toggle` with a gating route and one that does not gate.
  private static let nonGating = """
  use_cases:
    - id: toggle
      title: Dark mode
      value_tier: core
      intent: Readable at night.
      scenarios:
        - id: on-state
          when: [x]
          then: [y]
      validation:
        - id: unit-tests
          type: { kind: unit }
          covers: [on-state]
        - id: extra
          type: { kind: acceptance }
          covers: [on-state]
          gates_verification: false
          procedure:
            steps: [Look again.]

  """

  @Test
  func `a route that does not gate keeps its state and never lowers the use case`() throws {
    let fixture = try StatusFixture(definitions: Self.nonGating)
    try fixture.record("unit-tests")
    try fixture.record("extra", "fail")

    let useCase = try fixture.useCase()

    #expect(useCase.status == .verified)
    #expect(useCase.routes.map(\.status) == [.verified, .failed])
    #expect(useCase.routes.map(\.gates) == [true, false])
    #expect(useCase.decidingRoute?.identifier == "unit-tests")
  }

  @Test
  func `two runs of one store that share their first 8 digits are shown by different prefixes`()
    throws
  {
    let fixture = try StatusFixture(definitions: Self.nonGating)
    try fixture.record("unit-tests")
    try fixture.record("extra")

    let status = try fixture.status()
    let runs = status.useCases.flatMap(\.routes).compactMap { route -> String? in
      guard case let .decided(run, _) = route.explanation else {
        return nil
      }

      return run
    }
    let shown = runs.map(status.runIdentifiers.shortened)

    #expect(runs.count == 2)
    #expect(runs[0].prefix(8) == runs[1].prefix(8))
    #expect(shown[0] != shown[1])
    #expect(zip(runs, shown).allSatisfy { run, short in
      run.hasPrefix(short) && short.count >= 8
    })
  }

  @Test
  func `use cases are listed worst first, then drafts, then by id`() throws {
    let fixture = try StatusFixture(definitions: FreshnessSamples.multipleUseCases())
    try fixture.record("unit", "pass", useCase: "app.beta")
    try fixture.record("unit", "fail", useCase: "app.alpha")
    try fixture.record("manual", "pass", useCase: "app.alpha")

    let status = try fixture.status()

    #expect(status.useCases.map(\.identifier) == ["app.alpha", "app.beta", "app.gamma"])
    #expect(status.useCases.map(\.status) == [.failed, .verified, .draft])
  }

  @Test
  func `use cases in one state are ordered by id`() throws {
    let fixture = try StatusFixture(definitions: FreshnessSamples.multipleUseCases())

    let status = try fixture.status()

    #expect(status.useCases.map(\.identifier) == ["app.alpha", "app.beta", "app.gamma"])
    #expect(status.useCases.map(\.status) == [.unverified, .unverified, .draft])
  }

  // @use-case:validate.draft-or-ready#swift-tests.missing-field-is-draft
  @Test
  func `a draft says what it lacks and has no routes`() throws {
    let fixture = try StatusFixture(definitions: FreshnessSamples.multipleUseCases())

    let draft = try fixture.useCase("app.gamma")

    #expect(!draft.isReady)
    #expect(draft.status == .draft)
    #expect(draft.missing == ["value_tier"])
    #expect(draft.routes.isEmpty)
    #expect(draft.decidingRoute == nil)
  }

  // @use-case:end validate.draft-or-ready#swift-tests.missing-field-is-draft

  @Test
  func `a READY use case lacks nothing`() throws {
    let fixture = try StatusFixture()

    let useCase = try fixture.useCase()

    #expect(useCase.isReady)
    #expect(useCase.missing.isEmpty)
    #expect(useCase.title == "Dark mode")
    #expect(useCase.valueTier == "core")
  }

  // MARK: - Warnings

  @Test
  func `a use case with no links is warned about, and so is a route nothing reaches`() throws {
    let fixture = try StatusFixture()

    let warnings = try fixture.useCase().warnings

    #expect(warnings.map(\.kind) == [.noImplementationLinks, .routeNotLinked])
    #expect(warnings.map(\.isListed) == [false, false])
    #expect(warnings[0].text.contains("no implementation links"))
    #expect(warnings[1].text.contains("only `use-cases record` can verify it"))
    #expect(warnings[1].text.contains("unit-tests"))
  }

  @Test
  func `links take the warnings away`() throws {
    let fixture = try StatusFixture()
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#code", "work()")
        + LinkSamples.marked("app.toggle#unit-tests.check", "check()"),
    )

    #expect(try fixture.useCase().warnings.isEmpty)
  }

  @Test
  func `a route that does not gate is not warned about`() throws {
    let fixture = try StatusFixture(definitions: Self.nonGating)
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#code", "work()")
        + LinkSamples.marked("app.toggle#unit-tests.check", "check()"),
    )

    #expect(try fixture.useCase().warnings.isEmpty)
  }

  @Test
  func `a route that does not gate and has no links and no procedure is not warned about`() throws {
    let fixture = try StatusFixture(
      definitions: Self.nonGating.replacingOccurrences(
        of: "procedure:\n          steps: [Look again.]\n",
        with: "",
      ),
    )
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.toggle#code", "work()")
        + LinkSamples.marked("app.toggle#unit-tests.check", "check()"),
    )

    let useCase = try fixture.useCase()

    #expect(useCase.routes.map(\.isLinked) == [true, false])
    #expect(useCase.warnings.isEmpty)
  }

  @Test
  func `a draft is not warned about missing links`() throws {
    let fixture = try StatusFixture(definitions: FreshnessSamples.multipleUseCases())

    #expect(try fixture.useCase("app.gamma").warnings.isEmpty)
  }

  @Test
  func `an emptied marked region is the use case's own warning, listed, and not the workspace's`(
  ) throws {
    let fixture = try StatusFixture()
    try fixture.write(
      "src/a.swift",
      "// \(MarkerText.sentinel)app.toggle#code\n\n// \(MarkerText.sentinel)end app.toggle#code\n",
    )

    let status = try fixture.status()
    let useCase = try fixture.useCase()
    let empty = try #require(useCase.warnings.first { $0.kind == .markedRegionEmpty })

    #expect(
      empty.text == "src/a.swift:2: its marked region is empty; "
        + "if the code moved, move its markers with it",
    )
    #expect(empty.isListed)
    #expect(!useCase.warnings.contains { $0.kind == .noImplementationLinks })
    #expect(status.warnings.isEmpty)
  }

  @Test
  func `a marker for a use case that does not exist is a warning of the workspace`() throws {
    let fixture = try StatusFixture()
    try fixture.write(
      "src/a.swift",
      LinkSamples.marked("app.nothing#code", "work()"),
    )

    let status = try fixture.status()

    #expect(status.warnings.count == 1)
    #expect(status.warnings.first?.text(shortening: nil).contains("app.nothing") == true)
  }

  @Test
  func `a resource in excluded content is a warning of the workspace`() throws {
    let fixture = try StatusFixture(
      root: FreshnessSamples.root(exclude: ["vendor"]),
      definitions: FreshnessSamples
        .definitions(resources: [FreshnessSamples.file("vendor/a.json")]),
    )
    try fixture.write("vendor/a.json", "{}")

    let status = try fixture.status()

    #expect(status.warnings.count == 1)
  }

  // MARK: - Runs that never finished

  @Test
  func `a run folder with no marker is a warning and never evidence`() throws {
    let fixture = try StatusFixture()
    try fixture.record("manual")
    try fixture.record("unit-tests")
    try fixture.startRun(9)

    let status = try fixture.status()

    #expect(status.warnings == [.runNeverFinished(run: StoreFixture.identifier(9))])
    #expect(status.hasSealedRuns)
    #expect(try fixture.useCase().status == .verified)
  }

  @Test
  func `with nothing sealed, an unfinished run leaves the use case unverified`() throws {
    let fixture = try StatusFixture()
    try fixture.startRun(9)

    let status = try fixture.status()

    #expect(!status.hasSealedRuns)
    #expect(status.warnings.count == 1)
    #expect(try fixture.useCase().status == .unverified)
  }

  // MARK: - Refusals

  @Test
  func `a damaged store names every problem and infers nothing`() throws {
    let fixture = try StatusFixture()
    try fixture.record("manual")
    try fixture.write(".use-cases/runs/latest/note.txt", "x")
    try fixture.write(".use-cases/runs/other/note.txt", "x")

    let error = #expect(throws: StatusJudgingError.self) {
      try fixture.status()
    }

    guard case let .storage(problems)? = error else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return
    }

    #expect(problems.count == 2)
    #expect(
      problems.allSatisfy { problem in
        problem.hasSuffix("is not a run folder")
      },
    )
    #expect(error?.message.split(separator: "\n").count == 2)
  }

  @Test
  func `a resource that matches nothing makes the workspace invalid`() throws {
    let fixture = try StatusFixture(
      definitions: FreshnessSamples.definitions(resources: [FreshnessSamples.file("nope.json")]),
    )

    let error = #expect(throws: StatusJudgingError.self) {
      try fixture.status()
    }

    guard case let .invalidWorkspace(problems)? = error else {
      Issue.record("expected an invalid workspace, got \(String(describing: error))")
      return
    }

    #expect(!problems.isEmpty)
  }

  @Test
  func `a store whose schemas cannot load is a storage error`() throws {
    let fixture = try StatusFixture()
    let judge = StatusJudge(
      fingerprinter: RouteFingerprintComputer(),
      reading: .failure(.unreadable("missing")),
      promiseFingerprinter: PromiseFingerprinter(),
    )

    let error = #expect(throws: StatusJudgingError.self) {
      try fixture.status(using: judge)
    }

    guard case let .storage(problems)? = error else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return
    }

    #expect(problems.count == 1)
  }
}
