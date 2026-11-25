import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterOpeningTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  @discardableResult
  private func open() throws -> OpenRun {
    try fixture.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )
  }

  @Test
  func `a run is allocated the id the clock and the random bits make`() throws {
    let run = try open()

    #expect(run.identifier.text == "01a0d88fc5fbcdef0123456789abcdef")
    #expect(run.manifest.createdAt == "2026-09-25T12:34:56.123Z")
    #expect(run.manifest.kind == .record)
    #expect(run.workspace == fixture.workspace)
  }

  @Test
  func `the run's folder holds the initial manifest and an empty log, and no marker`() throws {
    let run = try open()
    let folder = ".use-cases/runs/\(run.identifier.text)"

    #expect(fixture.names(in: folder) == ["results.jsonl", "run.json"])
    #expect(try fixture.read("\(folder)/results.jsonl").isEmpty)
    #expect(try fixture.read("\(folder)/run.json").contains("\"kind\": \"record\""))
  }

  @Test
  func `the manifest is printed with a line feed after every line`() throws {
    let run = try open()
    let manifest = try fixture.read(".use-cases/runs/\(run.identifier.text)/run.json")

    #expect(manifest.hasPrefix("{\n  \"created_at\": "))
    #expect(manifest.hasSuffix("}\n"))
  }

  @Test
  func `the folder is published whole, so no temporary folder is left`() throws {
    let run = try open()

    #expect(fixture.names(in: ".use-cases/runs") == [run.identifier.text])
  }

  @Test
  func `the high-water mark is the new id, written as chapter 12 shows it`() throws {
    let run = try open()

    let expected = "{\"order_version\":1,\"last_run_id\":\"" + run.identifier.text + "\"}"

    #expect(try fixture.read(".use-cases/run-order.json") == expected)
  }

  @Test
  func `the lock file is in the store folder, never in runs`() throws {
    try open()

    #expect(fixture.names(in: ".use-cases") == ["allocation.lock", "run-order.json", "runs"])
  }

  @Test
  func `the open run is not evidence: the reader lists it as unfinished`() throws {
    let run = try open()

    let history = try fixture.readHistory()

    #expect(history.runs.isEmpty)
    #expect(history.unfinishedRuns.map(\.identifier) == [run.identifier])
  }

  @Test
  func `a workspace whose store folder is a file cannot be written`() throws {
    try fixture.directory.write(".use-cases", "not a folder")

    #expect(throws: StoreWritingError.self) {
      try open()
    }
  }
}
