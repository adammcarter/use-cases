import Foundation
import Testing
@testable import UseCasesCore

struct VerdictRecorderCommitTests {
  private let fixture: RecorderFixture

  init() throws {
    fixture = try RecorderFixture()
  }

  @Test
  func `a committed plan is a sealed run the reader reads`() throws {
    let plan = try fixture.plan(
      "app.toggle",
      "manual",
      "pass",
      message: "checked on staging",
    )

    let run = try fixture.recorder.commit(plan)

    let history = try fixture.readHistory()
    let stored = try #require(history.runs.first)
    #expect(stored.identifier.text == run.runIdentifier)
    #expect(stored.manifest?.kind == .record)
    #expect(stored.manifest?.createdAt == run.createdAt)
    #expect(stored.results.count == 1)

    let result = try #require(stored.results.first)
    #expect(result.useCase.text == "app.toggle")
    #expect(result.route.text == "manual")
    #expect(result.fingerprint.text == plan.fingerprint)
    #expect(result.verdict == .pass)
    #expect(result.detail?.origin == .recorded)
    #expect(result.detail?.message == "checked on staging")
    #expect(result.detail?.recordedAt == run.recordedAt)
  }

  @Test
  func `an empty note is no note: the log has no message`() throws {
    let plan = try fixture.plan(
      "app.toggle",
      "manual",
      "pass",
      message: "",
    )

    let run = try fixture.recorder.commit(plan)

    let stored = try #require(fixture.readHistory().runs.first)
    #expect(run.message == nil)
    #expect(stored.results.first?.detail?.message == nil)

    let log = try String(
      contentsOf: fixture.freshness.workspace.directory
        .location(of: ".use-cases/runs/\(run.runIdentifier)/results.jsonl"),
      encoding: .utf8,
    )
    #expect(!log.contains("message"))
  }

  @Test
  func `the recorded run says what was recorded`() throws {
    let plan = try fixture.plan(
      "app.toggle",
      "unit-tests",
      "incomplete",
    )

    let run = try fixture.recorder.commit(plan)

    #expect(run.useCase == "app.toggle")
    #expect(run.route == "unit-tests")
    #expect(run.status == "incomplete")
    #expect(run.fingerprint == plan.fingerprint)
    #expect(run.message == nil)
    #expect(run.createdAt == "2026-09-25T12:34:56.123Z")
    #expect(run.recordedAt == "2026-09-25T12:34:56.123Z")
    #expect(run.runIdentifier == "01a0d88fc5fbcdef0123456789abcdef")
  }

  @Test
  func `the verdict applies to the fingerprint it was recorded at`() throws {
    let plan = try fixture.plan(
      "app.toggle",
      "unit-tests",
    )
    _ = try fixture.recorder.commit(plan)

    let history = try fixture.readHistory()
    let fingerprint = try RouteFingerprint(validating: fixture.freshness
      .fingerprint(of: "unit-tests"))
    let applying = history.latestResult(
      useCase: .sample("app.toggle"),
      route: .sample("unit-tests"),
      fingerprint: fingerprint,
    )

    #expect(applying?.result.verdict == .pass)
  }

  @Test
  func `a later record of the same route is the newer evidence`() throws {
    _ = try fixture.recorder.commit(fixture.plan("app.toggle", "manual", "fail"))
    let second = try fixture.recorder.commit(fixture.plan("app.toggle", "manual", "pass"))

    let history = try fixture.readHistory()
    let fingerprint = try RouteFingerprint(validating: fixture.freshness.fingerprint(of: "manual"))
    let latest = history.latestResult(
      useCase: .sample("app.toggle"),
      route: .sample("manual"),
      fingerprint: fingerprint,
    )

    #expect(history.runs.count == 2)
    #expect(latest?.run.text == second.runIdentifier)
    #expect(latest?.result.verdict == .pass)
  }

  @Test
  func `a store that cannot be written is a storage error and records nothing`() throws {
    let plan = try fixture.plan(
      "app.toggle",
      "manual",
    )
    try fixture.freshness.write(".use-cases", "not a folder")

    let error = #expect(throws: RecordingError.self) {
      try fixture.recorder.commit(plan)
    }

    guard case .storage? = error else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return
    }
  }

  @Test
  func `schemas that cannot be loaded are a storage error and record nothing`() throws {
    let broken = try RecorderFixture(
      writing: .failure(.missing("run.schema.json")),
    )
    let plan = try broken.plan(
      "app.toggle",
      "manual",
    )

    let error = #expect(throws: RecordingError.self) {
      try broken.recorder.commit(plan)
    }

    guard case .storage? = error else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return
    }

    #expect(!broken.hasStore)
  }
}
