import Foundation
import Testing
@testable import UseCasesCore

struct VerifyFinisherGuardTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func edit(
    _ path: String,
    _ text: String,
  ) throws {
    try fixture.freshness.write(path, text)
  }

  /// Finishes a started run whose one link passed, after the test's edit.
  private func finish(
    _ started: StartedVerifyRun,
    reloading: FixtureReloading? = nil,
  ) async throws -> VerifiedRun {
    try fixture.writeReport(of: started)

    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response([fixture.linkKey(): "pass"]))],
    )

    return try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: reloading ?? FixtureReloading(fixture),
    )
  }

  private func changed(_ verified: VerifiedRun) throws -> [RunDiagnostic] {
    try #require(verified.manifest).diagnostics.filter {
      $0.problem == "code changed during the run"
    }
  }

  @Test
  func `code left alone gives a verdict and no diagnostic`() async throws {
    let verified = try await finish(fixture.start())

    #expect(verified.results.count == 1)
    #expect(try changed(verified).isEmpty)
  }

  @Test
  func `implementation code edited after the start gives no verdict, and names the file`()
    async throws
  {
    let started = try fixture.start()
    try edit(VerifyFixture.codeFile, LinkSamples.marked("app.toggle#draw", "draw(again)"))

    let verified = try await finish(started)
    let diagnostic = try #require(changed(verified).first { $0.route?.text == "unit-tests" })

    #expect(verified.results.isEmpty)
    #expect(diagnostic.files.map(\.text) == [VerifyFixture.codeFile])
    #expect(diagnostic.fingerprint != nil)
  }

  @Test
  func `a linked test edited after the start gives no verdict, even though its lines moved`()
    async throws
  {
    let started = try fixture.start()
    try edit(
      VerifyFixture.testFile,
      "// a line above\n" + LinkSamples.marked("app.toggle#unit-tests.renders", "check(more)"),
    )

    let verified = try await finish(started)
    let diagnostic = try #require(changed(verified).first)

    #expect(verified.results.isEmpty)
    #expect(diagnostic.files.map(\.text) == [VerifyFixture.testFile])
    #expect(!(verified.manifest?.diagnostics
        .contains { $0.problem == "its test didn't run" } ?? true))
  }

  @Test
  func `a file nothing links to can change and every verdict is kept`() async throws {
    let started = try fixture.start()
    try edit("notes.txt", "unrelated\n")

    let verified = try await finish(started)

    #expect(verified.results.count == 1)
    #expect(try changed(verified).isEmpty)
  }

  @Test
  func `an edit to another region of a linked file is a change of that file`() async throws {
    let started = try fixture.start()
    try edit(
      VerifyFixture.codeFile,
      LinkSamples.marked("app.toggle#draw", "draw()") + "// new tail outside the region\n",
    )

    let verified = try await finish(started)

    #expect(verified.results.count == 1)
    #expect(try changed(verified).isEmpty)
  }

  @Test
  func `the use case's own wording edited after the start gives no verdict`() async throws {
    let started = try fixture.start()
    let original = try fixture.read("use-cases/toggle.yml")

    try edit(
      "use-cases/toggle.yml",
      original.replacingOccurrences(of: "Readable at night.", with: "Readable by day."),
    )

    let verified = try await finish(started)
    let diagnostic = try #require(changed(verified).first { $0.route?.text == "unit-tests" })

    #expect(verified.results.isEmpty)
    #expect(diagnostic.files.isEmpty)
  }

  @Test
  func `a route the start point did not know has a bare diagnostic`() async throws {
    let started = try fixture.start()
    let original = try fixture.read("use-cases/toggle.yml")

    try edit(
      "use-cases/toggle.yml",
      original + "      - id: second\n        type: { kind: unit }\n        covers: [on-state]\n",
    )

    let verified = try await finish(started)
    let diagnostic = try #require(
      verified.manifest?.diagnostics.first { $0.route?.text == "second" },
    )

    #expect(diagnostic.problem == "code changed during the run")
    #expect(diagnostic.fingerprint == nil)
    #expect(diagnostic.files.isEmpty)
    #expect(diagnostic.links.isEmpty)
    #expect(verified.results.map(\.route.text) == ["unit-tests"])
  }

  @Test
  func `an edit made while the reports were read is caught by the second look`() async throws {
    let started = try fixture.start()
    let code = fixture.workspace.appendingPathComponent(VerifyFixture.codeFile)
    let reloading = FixtureReloading(fixture) {
      try? Data(LinkSamples.marked("app.toggle#draw", "draw(late)").utf8).write(to: code)
    }

    let verified = try await finish(
      started,
      reloading: reloading,
    )

    #expect(verified.results.isEmpty)
    #expect(try changed(verified).compactMap { $0.route?.text } == ["unit-tests"])
  }

  @Test
  func `a workspace that is invalid at the second look leaves the run open`() async throws {
    let started = try fixture.start()

    await #expect(throws: VerifyError.invalidWorkspace(problems: ["it broke"])) {
      try await finish(
        started,
        reloading: FixtureReloading(fixture, failure: .invalid(problems: ["it broke"])),
      )
    }

    #expect(try fixture.history().unfinishedRuns.count == 1)
    #expect(try fixture.history().runs.isEmpty)
  }

  @Test
  func `a request cancelled while the workspace is read again is sealed as interrupted`()
    async throws
  {
    let started = try fixture.start()

    let verified = try await finish(
      started,
      reloading: FixtureReloading(fixture, failure: .cancelled),
    )
    let run = try #require(try fixture.history().runs.first)

    #expect(verified.isCancelled)
    #expect(verified.results.isEmpty)
    #expect(verified.notes == ["cancelled before judging"])
    #expect(run.termination == .interrupted)
    #expect(try fixture.history().unfinishedRuns.isEmpty)
  }
}
