import Foundation
import Testing
@testable import UseCasesCore

struct VerifyAborterTests {
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

  private func runFolder(_ run: String) -> URL {
    fixture.freshness.workspace.directory.location(of: ".use-cases/runs/\(run)")
  }

  @Test
  func `the only open run is sealed as interrupted, with no results and the note aborted`()
    async throws
  {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)

    let aborted = try await abort()
    let sealed = try #require(try fixture.history().runs.first)

    #expect(aborted.runIdentifier == run)
    #expect(sealed.termination == .interrupted)
    #expect(sealed.results.isEmpty)
    #expect(sealed.manifest?.notes == ["aborted: closed by `use-cases verify --abort`"])
    #expect(try fixture.history().unfinishedRuns.isEmpty)
  }

  @Test
  func `the planned sources and the reports stay in the sealed run`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started, "half a report")

    _ = try await abort()

    let sealed = try #require(try fixture.history().runs.first)
    let report = try #require(started.reports.first).path

    #expect(sealed.manifest?.sources.map(\.identifier.text) == ["unit-tests"])
    #expect(FileManager.default.fileExists(atPath: report))
    #expect(try fixture.history().findings.isEmpty)
  }

  @Test
  func `an abort does not care that the settings changed since the start`() async throws {
    _ = try fixture.start()

    try fixture.freshness.write("use-cases-bridge.yml", "schema_version: 1\n")

    _ = try await abort()

    #expect(try fixture.history().runs.count == 1)
  }

  @Test
  func `with nothing open there is nothing to abort`() async {
    await #expect(throws: VerifyError.noOpenRun) {
      try await abort()
    }
  }

  @Test
  func `several open runs must be named, and the others stay open`() async throws {
    let first = try fixture.start()
    let second = try fixture.start()
    let ids = try [#require(first.runIdentifier), #require(second.runIdentifier)]

    await #expect(throws: VerifyError.severalOpenRuns(ids)) {
      try await abort()
    }

    _ = try await abort(ids[1])

    #expect(try fixture.history().unfinishedRuns.map(\.identifier.text) == [ids[0]])
  }

  @Test
  func `a sealed run cannot be aborted`() async throws {
    let run = try #require(try fixture.start().runIdentifier)

    _ = try await abort()

    await #expect(throws: VerifyError.alreadySealed(run)) {
      try await abort(run)
    }
  }

  @Test(arguments: ["nope", "0123"])
  func `a run id that names no run is refused`(text: String) async {
    await #expect(throws: VerifyError.noSuchRun(text)) {
      try await abort(text)
    }
  }

  @Test
  func `a run another process holds is being finished, and is left alone`() async throws {
    let run = try #require(try fixture.start().runIdentifier)

    let outcome = try await fixture.store.locks.holding(run: runFolder(run)) {
      await attempt()
    }

    #expect(throws: VerifyError.beingFinished(run)) {
      try outcome?.get()
    }
    #expect(try fixture.history().unfinishedRuns.count == 1)
  }

  private func attempt() async -> Result<AbortedVerifyRun, VerifyError> {
    do {
      return try await .success(abort())
    } catch {
      return .failure(error as? VerifyError ?? .storage("\(error)"))
    }
  }
}
