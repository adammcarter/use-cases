import Foundation
import Testing
@testable import UseCasesCore

/// A run whose own files are damaged is refused by name, never skipped (chapter 13 §6).
struct VerifyDamagedRunTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func stamp(of run: String) -> URL {
    fixture.runFolder(run).appendingPathComponent("start.json")
  }

  private func finish(_ run: String? = nil) async throws -> VerifiedRun {
    try await fixture.finisher(runner: MockTransformerRunner(answers: [])).finish(
      VerifyFinishRequest(runIdentifier: run),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )
  }

  private func abort(_ run: String? = nil) async throws -> AbortedVerifyRun {
    try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: run),
      in: fixture.workspace,
    )
  }

  /// A started run whose stamp is garbage, and a healthy one beside it.
  private func damagedAndHealthy() throws -> (damaged: String, healthy: String) {
    let damaged = try #require(try fixture.start().runIdentifier)
    let healthy = try #require(try fixture.start().runIdentifier)

    try Data("not json".utf8).write(to: stamp(of: damaged))

    return (damaged, healthy)
  }

  // Mutant: OpenRunFinder.find returns `.missing` for a run with an unreadable stamp, as
  // `try? readStamp` did. The plain commands then skip it and the first three tests fail.

  @Test
  func `a plain finish refuses a damaged run by name, as a storage error`() async throws {
    let (damaged, _) = try damagedAndHealthy()

    do {
      _ = try await finish()
      Issue.record("finished")
    } catch let error as VerifyError {
      guard case let .storage(message) = error else {
        Issue.record("not a storage error: \(error)")
        return
      }

      #expect(message.contains(".use-cases/runs/\(damaged)/start.json"))
      #expect(message.contains("--abort --run-id \(damaged)"))
    }
  }

  @Test
  func `a plain abort refuses it too, and closes nothing`() async throws {
    let (damaged, healthy) = try damagedAndHealthy()

    await #expect(throws: VerifyError.self) {
      try await abort()
    }
    #expect(try fixture.history().unfinishedRuns.map(\.identifier.text) == [damaged, healthy])
  }

  @Test
  func `a named finish of the damaged run is refused by name`() async throws {
    let (damaged, _) = try damagedAndHealthy()

    await #expect(throws: VerifyError.self) {
      try await finish(damaged)
    }
  }

  @Test
  func `abort with its run id closes a run whose stamp is garbage, as interrupted`() async throws {
    let (damaged, healthy) = try damagedAndHealthy()

    let aborted = try await abort(damaged)
    let history = try fixture.history()

    #expect(aborted.runIdentifier == damaged)
    #expect(history.runs.map(\.identifier.text) == [damaged])
    #expect(history.runs.first?.termination == .interrupted)
    #expect(history.unfinishedRuns.map(\.identifier.text) == [healthy])
    #expect(history.findings.isEmpty)
  }

  @Test
  func `after that the plain commands see only the healthy run`() async throws {
    let (damaged, healthy) = try damagedAndHealthy()

    _ = try await abort(damaged)
    let aborted = try await abort()

    #expect(aborted.runIdentifier == healthy)
  }

  @Test
  func `a verify run with no stamp cannot be sealed, so it is refused by name and left as it is`()
    async throws
  {
    let run = try #require(try fixture.start().runIdentifier)
    let manifest = try fixture.read(".use-cases/runs/\(run)/run.json")

    try FileManager.default.removeItem(at: stamp(of: run))

    do {
      _ = try await abort(run)
      Issue.record("aborted")
    } catch let error as VerifyError {
      guard case let .storage(message) = error else {
        Issue.record("not a storage error: \(error)")
        return
      }

      #expect(message.contains(".use-cases/runs/\(run)/start.json"))
    }

    #expect(try fixture.read(".use-cases/runs/\(run)/run.json") == manifest)
    #expect(try fixture.history().runs.isEmpty)
  }

  @Test
  func `an unsealed record run is not damaged, and is not a verify run to finish`() async throws {
    let run = try fixture.store.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )

    await #expect(throws: VerifyError.noSuchRun(run.identifier.text)) {
      try await fixture.finisher(runner: MockTransformerRunner(answers: [])).finish(
        VerifyFinishRequest(runIdentifier: run.identifier.text),
        in: fixture.resolved(),
        reloading: FixtureReloading(fixture),
      )
    }
    #expect(try fixture.store.openRuns(in: fixture.workspace).isEmpty)
  }

  @Test
  func `a start names the damaged run beside the open ones and is not stopped by it`() throws {
    let (damaged, _) = try damagedAndHealthy()

    let started = try fixture.start()

    #expect(started.isStarted)
    #expect(
      started.notes.contains { note in
        note.contains(".use-cases/runs/\(damaged)/start.json")
      },
    )
  }
}
