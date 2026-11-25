import Foundation
import Testing
@testable import UseCasesCore

/// For a version it supports a reader reads the rest and ignores fields it does not know
/// (chapter 12 §25).
struct StoreReaderUnknownMemberTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(42)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  @Test
  func `a result with a member this core does not know reads as the result without it`() throws {
    try fixture.sealRun(
      identifier,
      results: [StoreSamples.recordedResult().setting("confidence", "0.9")],
    )
    let plain = try StoreFixture()
    try plain.sealRun(identifier)

    let history = try StoreReader().readHistory(in: fixture.workspace)
    let expected = try StoreReader().readHistory(in: plain.workspace)

    #expect(history.runs.first?.results == expected.runs.first?.results)
  }

  @Test
  func `an attachment with a member this core does not know reads`() throws {
    let blobDigest = fixture.digest(of: "x")
    let attachment = JSONMembers([
      "name": "\"x\"",
      "blob": StoreSamples.quoted("uc-blob-v1-sha256:" + blobDigest),
      "size_bytes": "1",
      "colour": "\"red\"",
    ])
    let result = StoreSamples.recordedResult().setting("attachments", "[\(attachment.json)]")
    try fixture.sealRun(
      identifier,
      results: [result],
      blobs: [blobDigest: "x"],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.results.first?.detail?.attachments.count == 1)
    #expect(history.findings.isEmpty)
  }

  @Test
  func `a marker with a member this core does not know reads`() throws {
    try fixture.sealRun(
      identifier,
      marker: ["new_digest_kind": "{}"],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
    #expect(history.runs.first?.completion.details != nil)
  }

  @Test
  func `a manifest with a member this core does not know reads, in a source too`() throws {
    let source = StoreSamples.source.setting("host", "\"ci\"").json
    let manifest = StoreSamples.manifest(
      runIdentifier: identifier,
      kind: "verify",
      sources: "[\(source)]",
    ).setting("something_new", "{}")
    try fixture.sealRun(
      identifier,
      kind: "verify",
    )
    try replaceManifest(manifest)

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.manifest?.sources.count == 1)
  }

  @Test(arguments: [
    ("status", "1"),
    ("recorded_at", "7"),
    ("via", "\"record\""),
    ("message", "null"),
    ("route", "[]"),
  ])
  func `a known member of the wrong type is still corrupt`(
    name: String,
    value: String,
  ) throws {
    try fixture.sealRun(
      identifier,
      results: [StoreSamples.recordedResult().setting("confidence", "0.9").setting(name, value)],
    )

    let found = try fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("\(folder)/results.jsonl is corrupt: line 1: ") == true)
  }

  @Test
  func `a known member that is missing is still corrupt beside an unknown one`() throws {
    try fixture.sealRun(
      identifier,
      results: [StoreSamples.recordedResult().setting("confidence", "0.9").removing("status")],
    )

    #expect(try fixture.problems() == [
      "\(folder)/results.jsonl is corrupt: line 1: 'status' is a required property",
    ])
  }

  private func replaceManifest(_ manifest: JSONMembers) throws {
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
