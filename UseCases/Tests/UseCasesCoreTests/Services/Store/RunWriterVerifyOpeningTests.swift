import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterVerifyOpeningTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  private func open(_ draft: StartDraft? = nil) throws -> OpenRun {
    try fixture.writer.openVerifyRun(
      draft ?? StartDraft.sample(),
      in: fixture.workspace,
    )
  }

  @Test
  func `the run's folder holds the manifest, the log, the start stamp and the reports folders`()
    throws
  {
    let run = try open()
    let folder = ".use-cases/runs/\(run.identifier.text)"

    #expect(
      fixture.names(in: folder) == ["reports", "results.jsonl", "run.json", "start.json"],
    )
    #expect(fixture.names(in: "\(folder)/reports") == ["auth-tests"])
    #expect(fixture.names(in: "\(folder)/reports/auth-tests").isEmpty)
  }

  @Test
  func `every selected validation gets a reports folder`() throws {
    let run = try open(StartDraft.sample(selected: ["auth-tests", "style", "web-tests"]))

    #expect(
      fixture.names(in: ".use-cases/runs/\(run.identifier.text)/reports")
        == ["auth-tests", "style", "web-tests"],
    )
  }

  @Test
  func `the folder is published whole, so a crash never leaves a verify run without a stamp`()
    throws
  {
    let run = try open()

    #expect(fixture.names(in: ".use-cases/runs") == [run.identifier.text])
  }

  @Test
  func `the manifest is a verify run that plans its sources`() throws {
    let run = try open()

    #expect(run.manifest.kind == .verify)
    #expect(run.manifest.sources.map(\.identifier.text) == ["auth-tests"])
    #expect(try fixture.read(".use-cases/runs/\(run.identifier.text)/run.json").contains(
      "\"report\": \"reports/auth-tests/auth-tests.jsonl\"",
    ))
  }

  @Test
  func `the stamp is written to its schema, with the run's id and time`() throws {
    let run = try open(StartDraft.sample(openedBy: .run))
    let stamp = try fixture.read(".use-cases/runs/\(run.identifier.text)/start.json")

    #expect(stamp.contains("\"run_id\": \"\(run.identifier.text)\""))
    #expect(stamp.contains("\"started_at\": \"\(run.manifest.createdAt)\""))
    #expect(stamp.contains("\"opened_by\": \"run\""))
    #expect(stamp.contains("\"validations_sha256\": \"\(StoreSamples.digest("9"))\""))
    #expect(stamp.contains("\"Tests/AuthTests/LoginTests.swift\": "))
  }

  @Test
  func `an open verify run is listed as never finished and is not evidence`() throws {
    let run = try open()

    let history = try fixture.readHistory()

    #expect(history.runs.isEmpty)
    #expect(history.unfinishedRuns.map(\.identifier) == [run.identifier])
  }

  @Test
  func `a verify run is sealed with the digest of its stamp`() throws {
    let run = try open()

    _ = try fixture.writer.seal(
      run,
      termination: .interrupted,
    )

    let sealed = try fixture.read(".use-cases/runs/\(run.identifier.text)/completion.json")

    #expect(sealed.contains("\"start_sha256\""))
    #expect(try fixture.readHistory().findings.isEmpty)
  }
}
