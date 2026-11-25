import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderCorruptionTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(42)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  @Test(arguments: ["results.jsonl", "run.json", "completion.json"])
  func `a tampered sealed file is a storage error naming it and saying it is corrupt`(
    file: String,
  ) throws {
    try fixture.sealRecord(identifier)
    let path = "\(folder)/\(file)"
    let text = try fixture.read(path)
    let tampered = switch file {
    case "results.jsonl": text.replacingOccurrences(of: "\"pass\"", with: "\"fail\"")
    case "run.json": " " + text
    default: text.replacingOccurrences(of: "\"result_count\":1", with: "\"result_count\":0")
    }
    try fixture.write(path, tampered)

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("\(folder)/") == true)
    #expect(found.first?.contains(" is corrupt: ") == true)
  }

  @Test(arguments: [
    ("run.json", "it is not the file completion.json sealed: its digest differs"),
    ("results.jsonl", "it is not the file completion.json sealed: its digest differs"),
  ])
  func `a sealed file that is not the sealed bytes says its digest differs`(
    file: String,
    reason: String,
  ) throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/\(file)", " " + fixture.read("\(folder)/\(file)"))

    #expect(try fixture.problems() == ["\(folder)/\(file) is corrupt: \(reason)"])
  }

  @Test(arguments: ["run.json", "results.jsonl"])
  func `a sealed run missing a required file is corrupt`(file: String) throws {
    try fixture.sealRecord(identifier)
    try FileManager.default.removeItem(at: fixture.directory.location(of: "\(folder)/\(file)"))

    #expect(try fixture.problems() == ["\(folder)/\(file) is corrupt: the file is missing"])
  }

  @Test(arguments: ["run.json", "results.jsonl"])
  func `a sealed file that is a symlink is not followed and is corrupt`(file: String) throws {
    try fixture.sealRecord(identifier)
    let path = "\(folder)/\(file)"
    try fixture.write("\(folder)/elsewhere", fixture.read(path))
    try FileManager.default.removeItem(at: fixture.directory.location(of: path))
    try fixture.directory.symlink(path, to: "elsewhere")

    #expect(try fixture.problems() == ["\(path) is corrupt: it is a symlink, not a file"])
  }

  @Test
  func `a completion marker that is not JSON is corrupt`() throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/completion.json", "{")

    #expect(try fixture.problems() == [
      "\(folder)/completion.json is corrupt: it is not JSON: " +
        "the text ends before the document does",
    ])
  }

  @Test
  func `a marker that is not an object is corrupt`() throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/completion.json", "[]")

    #expect(try fixture
      .problems() == ["\(folder)/completion.json is corrupt: it is not a JSON object"])
  }

  @Test
  func `a marker with a byte order mark is corrupt`() throws {
    try fixture.sealRecord(identifier)
    let text = try fixture.read("\(folder)/completion.json")
    try fixture.directory.write(
      "\(folder)/completion.json",
      bytes: [0xEF, 0xBB, 0xBF] + Array(text.utf8),
    )

    #expect(try fixture.problems() == [
      "\(folder)/completion.json is corrupt: it starts with a byte order mark",
    ])
  }

  @Test
  func `a marker that is not UTF-8 is corrupt`() throws {
    try fixture.sealRecord(identifier)
    try fixture.directory.write("\(folder)/completion.json", bytes: [0x7B, 0xFF, 0x7D])

    #expect(try fixture.problems() == [
      "\(folder)/completion.json is corrupt: it is not valid UTF-8 text",
    ])
  }

  @Test
  func `a marker with a duplicate key is corrupt`() throws {
    try fixture.sealRecord(identifier)
    let text = try fixture.read("\(folder)/completion.json")
    try fixture.write(
      "\(folder)/completion.json",
      text.replacingOccurrences(of: "{", with: "{\"result_count\":1,"),
    )

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.contains("duplicate key 'result_count'") == true)
  }

  @Test(arguments: [
    ("termination", "\"crashed\""),
    ("result_count", "-1"),
    ("result_count", "\"1\""),
    ("manifest_sha256", "\"ABC\""),
    ("completion_version", "0"),
    ("completion_version", "\"1\""),
    ("completion_version", "1.5"),
  ])
  func `a marker that breaks the completion schema is corrupt`(
    name: String,
    value: String,
  ) throws {
    try fixture.sealRun(
      identifier,
      marker: [name: value],
    )

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("\(folder)/completion.json is corrupt: ") == true)
  }

  @Test
  func `a marker with a missing member is corrupt and says which`() throws {
    try fixture.sealRun(
      identifier,
      markerWithout: ["reports_sha256"],
    )

    #expect(try fixture.problems() == [
      "\(folder)/completion.json is corrupt: 'reports_sha256' is a required property",
    ])
  }

  @Test
  func `a marker for another run is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      marker: ["run_id": StoreSamples.quoted(StoreFixture.identifier(43))],
    )

    #expect(try fixture.problems() == [
      "\(folder)/completion.json is corrupt: its run_id \(StoreFixture.identifier(43)) " +
        "is not the folder's, \(identifier)",
    ])
  }

  @Test
  func `a manifest for another run is corrupt`() throws {
    try fixture.sealRecord(identifier)
    try resealManifest(StoreSamples.manifest(
      runIdentifier: StoreFixture.identifier(43),
      kind: "record",
    ))

    #expect(try fixture.problems() == [
      "\(folder)/run.json is corrupt: its run_id \(StoreFixture.identifier(43)) " +
        "is not the folder's, \(identifier)",
    ])
  }

  @Test(arguments: [
    ("kind", "\"batch\""),
    ("errors", "[\"\"]"),
    ("created_at", "\"yesterday\""),
    ("run_version", "0"),
  ])
  func `a manifest that breaks the run schema is corrupt`(
    name: String,
    value: String,
  ) throws {
    try fixture.sealRecord(identifier)
    try resealManifest(
      StoreSamples.manifest(
        runIdentifier: identifier,
        kind: "record",
      ).setting(name, value),
    )

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("\(folder)/run.json is corrupt: ") == true)
  }

  /// Replaces the manifest and marks the marker as sealing the new bytes.
  private func resealManifest(_ manifest: JSONMembers) throws {
    let old = try fixture.read("\(folder)/run.json")
    try fixture.write("\(folder)/run.json", manifest.json)
    try fixture.write(
      "\(folder)/completion.json",
      fixture.read("\(folder)/completion.json").replacingOccurrences(
        of: fixture.digest(of: old),
        with: fixture.digest(of: manifest.json),
      ),
    )
  }
}
