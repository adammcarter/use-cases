import Foundation
import Testing
@testable import UseCasesCore

/// A store written by a newer core stays readable by this one: it reads the envelope of each
/// file and leaves the rest alone (chapter 12 §25).
struct StoreReaderNewerVersionTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(0x2B)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  /// A run the way a newer core might write it: every file at version 2, with members this core
  /// does not know and some it does require missing.
  private func sealNewerRun(
    manifest: String? = nil,
    log: String? = nil,
    marker: [String: String] = [:],
    markerWithout: [String] = [],
  ) throws {
    let manifestText = manifest ?? newerManifest(identifier)
    let result = StoreSamples.recordedResult()
      .setting("record_version", "2")
      .setting("status", "\"pass\"")
      .setting("confidence", "0.99")
      .removing("via")
      .removing("recorded_at")
    let logText = log ?? result.json + "\n"

    try fixture.write("\(folder)/run.json", manifestText)
    try fixture.write("\(folder)/results.jsonl", logText)

    var completion = JSONMembers([
      "completion_version": "2",
      "run_id": StoreSamples.quoted(identifier),
      "result_count": "1",
      "manifest_sha256": StoreSamples.quoted(fixture.digest(of: manifestText)),
      "results_sha256": StoreSamples.quoted(fixture.digest(of: logText)),
      "new_digest_kind": "{}",
    ])
    for (name, value) in marker {
      completion = completion.setting(name, value)
    }
    for name in markerWithout {
      completion = completion.removing(name)
    }
    try fixture.write("\(folder)/completion.json", completion.json)
  }

  /// A manifest of version 2: a run id and a member this core has never heard of.
  private func newerManifest(_ runIdentifier: String) -> String {
    JSONMembers([
      "run_version": "2",
      "run_id": StoreSamples.quoted(runIdentifier),
      "something_new": "{}",
    ]).json
  }

  @Test
  func `a run from a newer core counts through its envelope`() throws {
    try fixture.sealRecord(StoreFixture.identifier(0x2A), status: "fail")
    try sealNewerRun()

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 2)
    let run = try #require(history.runs.last)
    #expect(run.identifier.text == identifier)
    #expect(run.manifest == nil)
    #expect(run.termination == nil)
    #expect(run.completion.details == nil)
    let result = try #require(run.results.first)
    #expect(result.verdict == .pass)
    #expect(result.detail == nil)

    let useCase = try UseCaseIdentifier(validating: StoreSamples.useCase)
    let route = try RouteIdentifier(validating: StoreSamples.route)
    let newest = history.latestResult(useCase: useCase, route: route)
    #expect(newest?.run.text == identifier)
    #expect(newest?.result.verdict == .pass)
  }

  @Test
  func `a newer manifest with a fingerprint of a newer format is history that never matches`(
  ) throws {
    let log = StoreSamples.recordedResult(fingerprint: "uc-route-v2-blake3:abc")
      .setting("record_version", "2").json + "\n"
    try sealNewerRun(log: log)

    let history = try StoreReader().readHistory(in: fixture.workspace)
    let useCase = try UseCaseIdentifier(validating: StoreSamples.useCase)
    let route = try RouteIdentifier(validating: StoreSamples.route)
    let current = try RouteFingerprint(validating: StoreSamples.fingerprint)

    #expect(history.latestResult(useCase: useCase, route: route) != nil)
    #expect(history.latestResult(useCase: useCase, route: route, fingerprint: current) == nil)
  }

  @Test
  func `each file's version is its own`() throws {
    // A version 1 marker over a version 2 manifest and a version 2 record.
    let manifestText = newerManifest(identifier)
    let logText = StoreSamples.recordedResult().setting("record_version", "2").json + "\n"
    try fixture.write("\(folder)/run.json", manifestText)
    try fixture.write("\(folder)/results.jsonl", logText)
    try fixture.write(
      "\(folder)/completion.json",
      StoreSamples.completion(
        runIdentifier: identifier,
        manifestDigest: fixture.digest(of: manifestText),
        resultsDigest: fixture.digest(of: logText),
      ).setting("outputs_sha256", "{}").setting("reports_sha256", "{}").json,
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let run = try #require(history.runs.first)
    #expect(run.completion.details != nil)
    #expect(run.manifest == nil)
    #expect(run.results.first?.detail == nil)
  }

  @Test(arguments: [
    ("run_id", "\"0000000000000000000000000000002a\""),
    ("result_count", "-1"),
    ("result_count", "\"1\""),
    ("manifest_sha256", "\"nope\""),
    ("results_sha256", "\"ABC\""),
    ("completion_version", "\"2\""),
    ("completion_version", "0"),
  ])
  func `a newer marker still has to be a sound envelope`(
    name: String,
    value: String,
  ) throws {
    try sealNewerRun(marker: [name: value])

    #expect(try fixture.problems().count == 1)
  }

  @Test(arguments: ["run_id", "result_count", "manifest_sha256", "results_sha256"])
  func `a newer marker missing an envelope member is corrupt`(name: String) throws {
    try sealNewerRun(markerWithout: [name])

    #expect(try fixture.problems().count == 1)
  }

  @Test
  func `a newer marker's digests are checked against the bytes`() throws {
    try sealNewerRun()
    try fixture.write("\(folder)/results.jsonl", " ")

    #expect(try fixture.problems() == [
      "\(folder)/results.jsonl is corrupt: it is not the file completion.json sealed: " +
        "its digest differs",
    ])
  }

  @Test
  func `a newer manifest for another run is corrupt`() throws {
    try sealNewerRun(manifest: newerManifest(StoreFixture.identifier(1)))

    #expect(try fixture.problems().first?.contains("is not the folder's") == true)
  }

  @Test
  func `a newer manifest without a run id is corrupt`() throws {
    try sealNewerRun(manifest: JSONMembers(["run_version": "2"]).json)

    #expect(try fixture.problems() == ["\(folder)/run.json is corrupt: run_id: this is required"])
  }

  @Test(arguments: [
    ("status", "\"skipped\""),
    ("use_case", "\"Not.Valid\""),
    ("fingerprint", "\"x\""),
    ("route", "1"),
  ])
  func `a newer record still has to be a sound envelope`(
    name: String,
    value: String,
  ) throws {
    let log = StoreSamples.recordedResult().setting("record_version", "2")
      .setting(name, value).json + "\n"
    try sealNewerRun(log: log)

    #expect(try fixture.problems().count == 1)
  }

  @Test(arguments: ["use_case", "route", "fingerprint", "status"])
  func `a newer record missing an envelope member is corrupt`(name: String) throws {
    let log = StoreSamples.recordedResult().setting("record_version", "2")
      .removing(name).json + "\n"
    try sealNewerRun(log: log)

    #expect(try fixture.problems().count == 1)
  }

  @Test
  func `a newer record is still one result per route`() throws {
    let line = StoreSamples.recordedResult().setting("record_version", "2").json + "\n"
    try sealNewerRun(log: line + line)

    #expect(try fixture.problems().first?.contains("repeats") == true)
  }
}
