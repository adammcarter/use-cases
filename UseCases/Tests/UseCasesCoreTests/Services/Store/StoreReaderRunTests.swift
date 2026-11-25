import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderRunTests {
  let fixture: StoreFixture

  init() throws {
    fixture = try StoreFixture()
  }

  @Test
  func `a sealed record run is read with its verdict`() throws {
    let identifier = StoreFixture.identifier(42)
    try fixture.sealRecord(identifier)

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let run = try #require(history.runs.first)
    #expect(history.runs.count == 1)
    #expect(run.identifier.text == identifier)
    #expect(run.manifest?.kind == .record)
    #expect(run.termination == .completed)
    #expect(run.findings.isEmpty)

    let result = try #require(run.results.first)
    #expect(result.useCase.text == StoreSamples.useCase)
    #expect(result.route.text == StoreSamples.route)
    #expect(result.fingerprint.text == StoreSamples.fingerprint)
    #expect(result.verdict == .pass)
    #expect(result.detail?.origin == .recorded)
    #expect(result.detail?.message == "checked by hand")
    #expect(result.detail?.recordedAt == StoreSamples.timestamp)
  }

  @Test
  func `a sealed verify run is read with its links, sources and diagnostics`() throws {
    let identifier = StoreFixture.identifier(42)
    try fixture.sealRun(
      identifier,
      kind: "verify",
      results: [StoreSamples.result(status: "fail")],
      start: StoreSamples.start,
      outputs: ["auth-tests/console.txt": "1 test failed\n"],
      reports: ["auth-tests/auth-tests.jsonl": "{}\n"],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let run = try #require(history.runs.first)
    let result = try #require(run.results.first)
    #expect(result.verdict == .fail)
    #expect(try result.detail?.origin == .validations(
      [IdentifierSegment(validating: "auth-tests")],
      links: [
        LinkResult(key: StoreSamples.linkKey, verdict: .fail),
        LinkResult(key: StoreSamples.otherLinkKey, verdict: nil),
      ],
    ))

    let manifest = try #require(run.manifest)
    #expect(manifest.kind == .verify)
    #expect(manifest.createdAt == StoreSamples.timestamp)
    #expect(manifest.sources.count == 1)
    #expect(manifest.sources.first?.identifier.text == "auth-tests")
    #expect(manifest.sources.first?.command == ["swift", "test"])
    #expect(manifest.sources.first?.exitCode == 1)
    #expect(manifest.sources.first?.seconds == 1.7)
    #expect(manifest.sources.first?.diagnostics == ["2 tests had no source line"])
    #expect(manifest.diagnostics.first?.problem == "its test didn't run")
    #expect(manifest.diagnostics.first?.links == [StoreSamples.linkKey])
    #expect(manifest.unlinkedTests.first?.line == 35)
    #expect(manifest.unlinkedTests.first?.status == .pass)
    #expect(run.completion.details?.startDigest == fixture.digest(of: StoreSamples.start.json))
  }

  @Test
  func `an unlinked test without a place is read`() throws {
    let identifier = StoreFixture.identifier(7)
    try fixture.sealRecord(identifier)
    try rewriteManifest(
      identifier,
      unlinked: #"[{"test":"T","file":null,"line":null,"status":"error"}]"#,
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let test = try #require(history.runs.first?.manifest?.unlinkedTests.first)
    #expect(test == UnlinkedTest(test: "T", file: nil, line: nil, status: .error))
  }

  @Test(arguments: ["pass", "fail", "incomplete", "error"])
  func `each verdict is read`(status: String) throws {
    try fixture.sealRecord(
      StoreFixture.identifier(1),
      status: status,
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.results.first?.verdict.rawValue == status)
  }

  @Test
  func `an interrupted run still counts and says so`() throws {
    try fixture.sealRun(
      StoreFixture.identifier(1),
      marker: ["termination": "\"interrupted\""],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.termination == .interrupted)
    #expect(history.runs.first?.results.count == 1)
  }

  @Test
  func `a run that judged nothing is sealed with no results`() throws {
    try fixture.sealRun(
      StoreFixture.identifier(1),
      results: [],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
    #expect(history.runs.first?.results.isEmpty == true)
  }

  @Test
  func `runs come back in ascending run id however the file system lists them`() throws {
    for number in [0x2B, 0x2A, 0x100, 0x9] {
      try fixture.sealRecord(StoreFixture.identifier(number))
    }

    let forward = try StoreReader().readHistory(in: fixture.workspace)
    let reversed = try StoreReader(fileSystem: ReversedListingFileSystem())
      .readHistory(in: fixture.workspace)

    let expected = [0x9, 0x2A, 0x2B, 0x100].map(StoreFixture.identifier)
    #expect(forward.runs.map(\.identifier.text) == expected)
    #expect(reversed.runs.map(\.identifier.text) == expected)
  }

  @Test
  func `a run id with a time in its top bits sorts after one from an earlier time`() throws {
    let earlier = "018f00000000" + String(repeating: "f", count: 20)
    let later = "018f00000001" + String(repeating: "0", count: 20)
    try fixture.sealRecord(later)
    try fixture.sealRecord(earlier)

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.map(\.identifier.text) == [earlier, later])
  }

  @Test
  func `a recognized temporary folder is not a run`() throws {
    try fixture.sealRecord(StoreFixture.identifier(1))
    try fixture.write(".use-cases/runs/\(StoreLayout.temporaryRunPrefix)abc/run.json", "{")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
    #expect(history.unfinishedRuns.isEmpty)
  }

  @Test
  func `a result is read with an attachment that is intact`() throws {
    let content = "all good\n"
    let blobDigest = fixture.digest(of: content)
    let result = StoreSamples.recordedResult().setting(
      "attachments",
      """
      [{"name":"log.txt","blob":"uc-blob-v1-sha256:\(blobDigest)",\
      "size_bytes":\(content.utf8.count),"media_type":"text/plain"}]
      """,
    )
    try fixture.sealRun(
      StoreFixture.identifier(1),
      results: [result],
      blobs: [blobDigest: content],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let attachment = try #require(history.runs.first?.results.first?.detail?.attachments.first)
    #expect(attachment.name == "log.txt")
    #expect(attachment.digest == blobDigest)
    #expect(attachment.sizeBytes == 9)
    #expect(attachment.mediaType == "text/plain")
    #expect(history.findings.isEmpty)
  }

  /// Replaces a manifest's unlinked tests and re-seals the marker around the new bytes.
  private func rewriteManifest(
    _ identifier: String,
    unlinked: String,
  ) throws {
    let manifest = StoreSamples.manifest(
      runIdentifier: identifier,
      kind: "record",
    ).setting("unlinked_tests", unlinked)
    let folder = StoreFixture.folder(identifier)
    try fixture.write("\(folder)/run.json", manifest.json)

    let marker = try fixture.read("\(folder)/completion.json")
    let old = fixture.digest(of: StoreSamples.manifest(
      runIdentifier: identifier,
      kind: "record",
    ).json)
    try fixture.write(
      "\(folder)/completion.json",
      marker.replacingOccurrences(of: old, with: fixture.digest(of: manifest.json)),
    )
  }
}
