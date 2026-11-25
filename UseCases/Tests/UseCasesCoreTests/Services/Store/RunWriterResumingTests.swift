import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterResumingTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  private func openRun() throws -> OpenRun {
    try fixture.writer.openVerifyRun(
      StartDraft.sample(),
      in: fixture.workspace,
    )
  }

  @Test
  func `a run opened earlier is taken up with the manifest on disk`() throws {
    let opened = try openRun()

    let resumed = try fixture.writer.reopenRun(
      opened.identifier,
      in: fixture.workspace,
    )

    #expect(resumed == opened)
  }

  @Test
  func `a sealed run cannot be taken up`() throws {
    let opened = try openRun()

    _ = try fixture.writer.seal(
      opened,
      termination: .interrupted,
    )

    #expect(throws: StoreWritingError.sealed(opened.identifier)) {
      try fixture.writer.reopenRun(
        opened.identifier,
        in: fixture.workspace,
      )
    }
  }

  @Test
  func `a run that is not there cannot be taken up`() {
    #expect(throws: StoreWritingError.self) {
      try fixture.writer.reopenRun(
        .sample(7),
        in: fixture.workspace,
      )
    }
  }

  @Test
  func `the finalized manifest replaces the initial one, whole`() throws {
    let opened = try openRun()
    let finalized = opened.manifest.adding(note: "aborted: closed by `use-cases verify --abort`")

    try fixture.writer.finalize(
      finalized,
      of: opened,
    )

    let reopened = try fixture.writer.reopenRun(
      opened.identifier,
      in: fixture.workspace,
    )

    #expect(reopened.manifest == finalized)
    #expect(fixture.names(in: ".use-cases/runs/\(opened.identifier.text)").sorted() == [
      "reports", "results.jsonl", "run.json", "start.json",
    ])
  }

  @Test
  func `a manifest of another run is refused`() throws {
    let opened = try openRun()
    let other = RunManifest(
      identifier: .sample(9),
      createdAt: opened.manifest.createdAt,
      kind: .verify,
      sources: [],
      errors: [],
      diagnostics: [],
      unlinkedTests: [],
      notes: [],
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.finalize(
        other,
        of: opened,
      )
    }
  }

  @Test
  func `a sealed run's manifest is never replaced`() throws {
    let opened = try openRun()

    _ = try fixture.writer.seal(
      opened,
      termination: .interrupted,
    )

    #expect(throws: StoreWritingError.sealed(opened.identifier)) {
      try fixture.writer.finalize(
        opened.manifest.adding(note: "late"),
        of: opened,
      )
    }
  }

  @Test
  func `a finalized manifest breaks no schema or the run is not sealed`() throws {
    let opened = try openRun()
    let broken = RunManifest(
      identifier: opened.identifier,
      createdAt: opened.manifest.createdAt,
      kind: .verify,
      sources: [],
      errors: [""],
      diagnostics: [],
      unlinkedTests: [],
      notes: [],
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.finalize(
        broken,
        of: opened,
      )
    }
    #expect(try fixture.readHistory().unfinishedRuns.count == 1)
  }
}
