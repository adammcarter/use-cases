import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// Judge first, then the guard on the verdicts (chapter 13 §7 steps 5 and 6).
struct VerifyFinisherJudgingOrderTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func finish(
    _ started: StartedVerifyRun,
    answering statuses: [String: String]? = nil,
    reloading: FixtureReloading? = nil,
  ) async throws -> VerifiedRun {
    try fixture.writeReport(of: started)

    let answers = try statuses ?? [fixture.linkKey(): "pass"]
    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response(answers))])

    return try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: reloading ?? FixtureReloading(fixture),
    )
  }

  private func editCode() throws {
    try fixture.freshness.write(
      VerifyFixture.codeFile,
      LinkSamples.marked("app.toggle#draw", "draw(again)"),
    )
  }

  private func diagnostics(
    of verified: VerifiedRun,
    route: String,
  ) -> [String] {
    (verified.manifest?.diagnostics ?? [])
      .filter { $0.route?.text == route }
      .map(\.problem)
  }

  // MARK: - D5: the order of judging and the guard

  // Mutant: FinishPoint+Judging withholds a route on the guard before it is judged (the old
  // `withheld` pass). `manual` then gets "code changed during the run".

  @Test
  func `a route only a person can speak for never gets "code changed during the run"`(
  ) async throws {
    let started = try fixture.start()

    try editCode()

    let verified = try await finish(started)

    #expect(diagnostics(of: verified, route: "manual").isEmpty)
    #expect(diagnostics(of: verified, route: "unit-tests") == ["code changed during the run"])
  }

  // Mutant: the same. `unit-tests` has no result and its code changed; the old order says "code
  // changed", the chapter says the test did not run.

  @Test
  func `a route with no verdict keeps its own reason when the code changed`() async throws {
    let started = try fixture.start()

    try editCode()

    let verified = try await finish(
      started,
      answering: [:],
    )

    #expect(diagnostics(of: verified, route: "unit-tests") == ["its test didn't run"])
    #expect(verified.results.isEmpty)
  }

  @Test
  func `a partial run says what it read on a route whose test it did not read`() async throws {
    let two = try VerifyFixture(bridge: Self.twoValidations)
    let started = try two.start(only: ["unit-tests"])

    try two.writeReport(of: started)

    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response([:]))])
    let verified = try await two.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: two.resolved(),
      reloading: FixtureReloading(two),
    )

    #expect(
      diagnostics(of: verified, route: "unit-tests")
        == ["its test didn't run (this run read only unit-tests)"],
    )
  }

  @Test
  func `a run that selects every validation keeps the plain reason`() async throws {
    let started = try fixture.start(only: ["unit-tests"])

    let verified = try await finish(
      started,
      answering: [:],
    )

    #expect(diagnostics(of: verified, route: "unit-tests") == ["its test didn't run"])
  }

  @Test
  func `a route with a verdict and changed code loses the verdict to the guard`() async throws {
    let started = try fixture.start()

    try editCode()

    let verified = try await finish(started)

    #expect(verified.results.isEmpty)
    #expect(diagnostics(of: verified, route: "unit-tests") == ["code changed during the run"])
  }

  @Test
  func `a route added during the run that only a person can speak for says nothing`() async throws {
    let started = try fixture.start()
    let original = try fixture.read("use-cases/toggle.yml")

    try fixture.freshness.write(
      "use-cases/toggle.yml",
      original + "      - id: walkthrough\n        type: { kind: acceptance }\n"
        + "        covers: [on-state]\n        procedure:\n          steps: [Look.]\n",
    )

    let verified = try await finish(started)

    #expect(diagnostics(of: verified, route: "walkthrough").isEmpty)
    #expect(verified.results.map(\.route.text) == ["unit-tests"])
  }

  // MARK: - D6: which files moved

  // Mutant: Guardian.moved does not fall back to the start files. A route that lost its links
  // names no file.

  @Test
  func `a route that lost its links names every start file that moved`() async throws {
    let started = try fixture.start()
    let code = fixture.workspace.appendingPathComponent(VerifyFixture.codeFile)
    let test = fixture.workspace.appendingPathComponent(VerifyFixture.testFile)

    let reloading = FixtureReloading(fixture) {
      try? Data("// no marker any more\n".utf8).write(to: code)
      try? Data("// no marker either\n".utf8).write(to: test)
    }

    let verified = try await finish(
      started,
      reloading: reloading,
    )
    let diagnostic = try #require(
      verified.manifest?.diagnostics.first {
        $0.route?.text == "unit-tests" && $0.problem == "code changed during the run"
      },
    )

    #expect(diagnostic.files.map(\.text) == [VerifyFixture.codeFile, VerifyFixture.testFile])
    #expect(diagnostic.fingerprint != nil)
  }

  @Test
  func `a route that still has links names only its own files that moved`() async throws {
    let started = try fixture.start()

    try editCode()

    let verified = try await finish(started)
    let diagnostic = try #require(
      verified.manifest?.diagnostics.first { $0.route?.text == "unit-tests" },
    )

    #expect(diagnostic.files.map(\.text) == [VerifyFixture.codeFile])
  }

  // MARK: - D7: the settings the run was started with

  private static let twoValidations =
    BridgeFileSamples.validation(lines: ["report: unit.xml"])
      + "  - id: style\n    report: style.txt\n    transformer: exit-code\n"

  // Mutant: FinishPoint+Reading maps `stamp.selected` onto the current validations in the
  // start's order, so moving them in the file goes unnoticed.

  @Test
  func `validations moved in the file since the start are a change`() async throws {
    let two = try VerifyFixture(bridge: Self.twoValidations)
    let started = try two.start()

    try two.freshness.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nvalidations:\n  - id: style\n    report: style.txt\n"
        + "    transformer: exit-code\n  - id: unit-tests\n    report: unit.xml\n"
        + "    transformer: junit\n",
    )

    let run = try #require(started.runIdentifier)
    await #expect(throws: VerifyError.settingsChanged(run: run)) {
      try await two.finisher(runner: MockTransformerRunner(answers: [])).finish(
        VerifyFinishRequest(runIdentifier: nil),
        in: two.resolved(),
        reloading: FixtureReloading(two),
      )
    }
  }

  @Test
  func `a selected validation that was removed is a change`() async throws {
    let two = try VerifyFixture(bridge: Self.twoValidations)
    let started = try two.start()

    try two.freshness.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(lines: ["report: unit.xml"]),
    )

    let run = try #require(started.runIdentifier)
    await #expect(throws: VerifyError.settingsChanged(run: run)) {
      try await two.finisher(runner: MockTransformerRunner(answers: [])).finish(
        VerifyFinishRequest(runIdentifier: nil),
        in: two.resolved(),
        reloading: FixtureReloading(two),
      )
    }
  }

  @Test
  func `with no validations an only that names one is a usage refusal, not nothing to start`()
    throws
  {
    let bare = try VerifyFixture(bridge: nil)

    #expect(
      throws: VerifyError.unknownValidations(
        ["unit-tests"],
        known: [],
      ),
    ) {
      try bare.start(only: ["unit-tests"])
    }
    #expect(bare.runs().isEmpty)
  }
}
