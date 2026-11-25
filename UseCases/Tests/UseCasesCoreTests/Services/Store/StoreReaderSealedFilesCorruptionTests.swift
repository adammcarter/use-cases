import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderSealedFilesCorruptionTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(42)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  @Test
  func `a marker without a start digest beside a start stamp is corrupt`() throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/start.json", StoreSamples.start.json)

    #expect(try fixture.problems() == [
      "\(folder)/start.json is corrupt: completion.json has no start_sha256 for it",
    ])
  }

  @Test
  func `a start digest with no start stamp is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      marker: ["start_sha256": StoreSamples.quoted(StoreSamples.digest("e"))],
    )

    #expect(try fixture.problems() == ["\(folder)/start.json is corrupt: the file is missing"])
  }

  @Test
  func `a start stamp that is not the sealed bytes is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      kind: "verify",
      start: StoreSamples.start,
    )
    try fixture.write("\(folder)/start.json", StoreSamples.start.json + " ")

    #expect(try fixture.problems() == [
      "\(folder)/start.json is corrupt: it is not the file completion.json sealed: " +
        "its digest differs",
    ])
  }

  @Test
  func `a console capture that is not the sealed bytes is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      outputs: ["auth-tests/console.txt": "ok\n"],
    )
    try fixture.write("\(folder)/outputs/auth-tests/console.txt", "tampered\n")

    #expect(try fixture.problems() == [
      "\(folder)/outputs/auth-tests/console.txt is corrupt: it is not the file " +
        "completion.json sealed: its digest differs",
    ])
  }

  @Test
  func `a console capture that has gone is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      outputs: ["auth-tests/console.txt": "ok\n"],
    )
    try FileManager.default.removeItem(
      at: fixture.directory.location(of: "\(folder)/outputs/auth-tests/console.txt"),
    )

    #expect(try fixture.problems() == [
      "\(folder)/outputs is corrupt: outputs do not match completion.json",
    ])
  }

  @Test(arguments: ["record", "verify"])
  func `a console capture added after sealing is corrupt`(kind: String) throws {
    try fixture.sealRun(
      identifier,
      kind: kind,
    )
    try fixture.write("\(folder)/outputs/late/console.txt", "late\n")

    #expect(try fixture.problems() == [
      "\(folder)/outputs is corrupt: outputs do not match completion.json",
    ])
  }

  @Test
  func `a console capture added beside a sealed one is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      outputs: ["auth-tests/console.txt": "ok\n"],
    )
    try fixture.write("\(folder)/outputs/auth-tests/extra.txt", "x")

    #expect(try fixture.problems() == [
      "\(folder)/outputs is corrupt: outputs do not match completion.json",
    ])
  }

  @Test
  func `an empty folder under outputs is not a file`() throws {
    try fixture.sealRun(identifier)
    try fixture.directory.makeDirectory("\(folder)/outputs/empty")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
  }

  @Test
  func `a symlink added under outputs is not followed and does not match`() throws {
    try fixture.sealRun(identifier)
    try fixture.write("\(folder)/elsewhere.txt", "x")
    try fixture.directory.symlink("\(folder)/outputs/link.txt", to: "../elsewhere.txt")

    #expect(try fixture.problems() == [
      "\(folder)/outputs is corrupt: outputs do not match completion.json",
    ])
  }

  @Test
  func `a verify run with no start stamp is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      kind: "verify",
      markerWithout: ["start_sha256"],
    )
    try FileManager.default.removeItem(at: fixture.directory.location(of: "\(folder)/start.json"))

    #expect(try fixture.problems() == [
      "\(folder)/start.json is corrupt: a verify run has no start stamp",
    ])
  }

  @Test
  func `a console capture behind a symlinked folder is not followed`() throws {
    try fixture.sealRun(
      identifier,
      outputs: ["auth-tests/console.txt": "ok\n"],
    )
    let outputs = "\(folder)/outputs/auth-tests"
    try fixture.write("\(folder)/other/console.txt", "ok\n")
    try FileManager.default.removeItem(at: fixture.directory.location(of: outputs))
    try fixture.directory.symlink(outputs, to: "../other")

    #expect(try fixture.problems() == [
      "\(folder)/outputs is corrupt: outputs do not match completion.json",
    ])
  }

  @Test
  func `every damaged file of one run is reported`() throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/run.json", "{}")
    try fixture.write("\(folder)/results.jsonl", "{}\n")

    #expect(try fixture.problems().count == 2)
  }
}
