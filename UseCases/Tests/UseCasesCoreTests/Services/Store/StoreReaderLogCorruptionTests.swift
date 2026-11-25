import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderLogCorruptionTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(42)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  @Test
  func `a result count that disagrees with the log is corrupt`() throws {
    try fixture.sealRun(
      identifier,
      marker: ["result_count": "2"],
    )

    #expect(try fixture.problems() == [
      "\(folder)/results.jsonl is corrupt: it holds 1 results, but completion.json says 2",
    ])
  }

  @Test
  func `two results for one route are corrupt even with different fingerprints`() throws {
    try fixture.sealRun(
      identifier,
      results: [
        StoreSamples.recordedResult(),
        StoreSamples.recordedResult(fingerprint: StoreSamples.otherFingerprint),
      ],
    )

    #expect(try fixture.problems() == [
      "\(folder)/results.jsonl is corrupt: line 2 repeats " +
        "\(StoreSamples.useCase) \(StoreSamples.route)",
    ])
  }

  @Test(arguments: [
    ("status", "\"skipped\""),
    ("status", "\"verified\""),
    ("fingerprint", "\"sha256:x\""),
    ("use_case", "\"Not.Valid\""),
    ("via", "[]"),
    ("recorded_at", "\"yesterday\""),
    ("record_version", "0"),
  ])
  func `a result that breaks the result schema is corrupt and names its line`(
    name: String,
    value: String,
  ) throws {
    try fixture.sealRun(
      identifier,
      results: [
        StoreSamples.recordedResult(route: "first"),
        StoreSamples.recordedResult().setting(name, value),
      ],
    )

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("\(folder)/results.jsonl is corrupt: line 2: ") == true)
  }

  @Test
  func `a result that is not JSON is corrupt and names its line`() throws {
    try writeLog("{\"a\":1}\nnot json\n", resultCount: 2)

    #expect(try fixture.problems().first?.hasPrefix(
      "\(folder)/results.jsonl is corrupt: line 1: ",
    ) == true)
  }

  @Test
  func `a log with no final line feed is corrupt`() throws {
    try writeLog(StoreSamples.recordedResult().json, resultCount: 1)

    #expect(try fixture.problems() == [
      "\(folder)/results.jsonl is corrupt: the last line has no line feed",
    ])
  }

  @Test(arguments: [
    ("\n", 1),
    ("\n\n", 2),
  ])
  func `a blank line in a log is corrupt`(
    text: String,
    count: Int,
  ) throws {
    try writeLog(text, resultCount: count)

    #expect(try fixture.problems().first?.contains("line 1 is blank") == true)
  }

  @Test
  func `a blank line between results is corrupt`() throws {
    let line = StoreSamples.recordedResult().json
    try writeLog("\(line)\n\n\(line)\n", resultCount: 2)

    #expect(try fixture.problems().first?.contains("line 2 is blank") == true)
  }

  @Test
  func `a log with a byte order mark is corrupt`() throws {
    let line = StoreSamples.recordedResult().json
    try writeLog("\u{FEFF}\(line)\n", resultCount: 1)

    #expect(try fixture.problems().first?
      .contains("line 1: it starts with a byte order mark") == true)
  }

  @Test
  func `a log with Windows line endings reads, as JSON allows the carriage return`() throws {
    let line = StoreSamples.recordedResult().json
    try writeLog("\(line)\r\n", resultCount: 1)

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.results.count == 1)
  }

  /// Writes a log and a marker that digests it and counts the given number of results.
  private func writeLog(
    _ text: String,
    resultCount: Int,
  ) throws {
    try fixture.sealRecord(identifier)
    try fixture.write("\(folder)/results.jsonl", text)
    try fixture.write(
      "\(folder)/completion.json",
      StoreSamples.completion(
        runIdentifier: identifier,
        resultCount: resultCount,
        manifestDigest: fixture.digest(of: fixture.read("\(folder)/run.json")),
        resultsDigest: fixture.digest(of: text),
      ).setting("outputs_sha256", "{}").setting("reports_sha256", "{}").json,
    )
  }
}
