import Foundation
import Testing
@testable import UseCasesCore

/// An abort drops what an unfinished finish staged (chapter 13 §6): staged lines are never
/// evidence, whole or torn.
struct VerifyAborterStagedResultsTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func aborted(staging text: String) async throws -> StoredRun {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)

    try fixture.stage(text, in: run)
    _ = try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: nil),
      in: fixture.workspace,
    )

    return try #require(try fixture.history().runs.first)
  }

  // Mutant: VerifyAborter.close does not call `clearResults`. The whole line is then sealed as a
  // verdict, and the torn tail makes the seal refuse the log as corrupt.

  @Test
  func `a complete staged line is dropped: the sealed run has no result`() async throws {
    let sealed = try await aborted(staging: fixture.stagedResultLine())

    #expect(sealed.results.isEmpty)
    #expect(sealed.completion.resultCount == 0)
    #expect(sealed.termination == .interrupted)
  }

  @Test
  func `a torn tail is dropped and the run is sealed`() async throws {
    let line = try fixture.stagedResultLine()
    let sealed = try await aborted(staging: String(line.dropLast(40)))

    #expect(sealed.results.isEmpty)
    #expect(sealed.completion.resultCount == 0)
    #expect(sealed.termination == .interrupted)
  }

  @Test
  func `whole lines and then a torn one are dropped together`() async throws {
    let line = try fixture.stagedResultLine()
    let sealed = try await aborted(staging: line + String(line.dropLast(10)))

    #expect(sealed.results.isEmpty)
  }

  @Test
  func `a staged verdict never reaches the status of its route`() async throws {
    _ = try await aborted(staging: fixture.stagedResultLine())

    let history = try fixture.history()

    #expect(
      history.results(
        useCase: .sample("app.toggle"),
        route: .sample("unit-tests"),
      ).isEmpty,
    )
  }

  @Test
  func `the log is empty in the sealed run, and its digest is that of nothing`() async throws {
    let sealed = try await aborted(staging: fixture.stagedResultLine())
    let log = try fixture.read(".use-cases/runs/\(sealed.identifier.text)/results.jsonl")

    #expect(log.isEmpty)
    #expect(sealed.completion.resultsDigest == SHA256Hasher().sha256Hex(of: []))
  }

  @Test
  func `the refusal a second finish gives names the abort, and the abort now works`()
    async throws
  {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)

    try fixture.stage(fixture.stagedResultLine(), in: run)

    let refusal = VerifyError.stagedResults(run: run)
    await #expect(throws: refusal) {
      try await fixture.finisher(runner: MockTransformerRunner(answers: [])).finish(
        VerifyFinishRequest(runIdentifier: nil),
        in: fixture.resolved(),
        reloading: FixtureReloading(fixture),
      )
    }
    #expect(refusal.message.contains("--abort --run-id \(run)"))

    _ = try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: run),
      in: fixture.workspace,
    )

    #expect(try fixture.history().runs.map(\.identifier.text) == [run])
  }
}
