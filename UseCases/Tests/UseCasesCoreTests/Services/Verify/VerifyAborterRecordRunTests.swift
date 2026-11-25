import Foundation
import Testing
@testable import UseCasesCore

/// A `record` run cut off mid-write is open for good unless `--abort` closes it (chapter 13 §15).
struct VerifyAborterRecordRunTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func abort(_ runIdentifier: String? = nil) async throws -> AbortedVerifyRun {
    try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: runIdentifier),
      in: fixture.workspace,
    )
  }

  /// A record run whose process died before it sealed it: published, and nobody holds it.
  private func cutOffRecordRun() throws -> OpenRun {
    try fixture.store.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )
  }

  @Test
  func `the only open run is a cut-off record run, and abort seals it interrupted with no results`()
    async throws
  {
    let run = try cutOffRecordRun()

    let aborted = try await abort()
    let sealed = try #require(try fixture.history().runs.first)

    #expect(aborted.runIdentifier == run.identifier.text)
    #expect(sealed.termination == .interrupted)
    #expect(sealed.results.isEmpty)
    #expect(sealed.manifest?.notes == ["aborted: closed by `use-cases verify --abort`"])
    #expect(try fixture.history().unfinishedRuns.isEmpty)
  }

  @Test
  func `a result the cut-off record had staged is dropped, never evidence`() async throws {
    let run = try cutOffRecordRun()
    try fixture.stage(
      fixture.stagedResultLine(),
      in: run.identifier.text,
    )

    _ = try await abort(run.identifier.text)

    #expect(try fixture.history().runs.first?.results.isEmpty == true)
  }

  @Test
  func `a cut-off record run is named with run-id like any other`() async throws {
    let record = try cutOffRecordRun()
    _ = try fixture.start()

    let aborted = try await abort(record.identifier.text)

    #expect(aborted.runIdentifier == record.identifier.text)
  }

  @Test
  func `a cut-off record run beside a started run is one of several, and the person names one`()
    async throws
  {
    let record = try cutOffRecordRun()
    let started = try #require(try fixture.start().runIdentifier)

    await #expect(throws: VerifyError.severalOpenRuns([record.identifier.text, started])) {
      try await abort()
    }
  }

  @Test
  func `a record run that is being written is held, so abort leaves it alone`() async throws {
    let held = try fixture.store.writer.openHeldRun(
      kind: .record,
      in: fixture.workspace,
    )

    await #expect(throws: VerifyError.beingFinished(held.run.identifier.text)) {
      try await abort()
    }

    held.lock.release()

    let aborted = try await abort()

    #expect(aborted.runIdentifier == held.run.identifier.text)
  }

  @Test
  func `a sealed record run cannot be aborted`() async throws {
    let run = try cutOffRecordRun()
    _ = try fixture.store.writer.seal(
      run,
      termination: .completed,
    )

    await #expect(throws: VerifyError.alreadySealed(run.identifier.text)) {
      try await abort(run.identifier.text)
    }
  }
}
