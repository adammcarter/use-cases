import Foundation
import Testing
@testable import UseCasesCore

/// Damage beside the verdicts is reported and never rewrites them (chapter 12 §15 and §17).
struct StoreReaderFindingsTests {
  let fixture: StoreFixture
  let identifier = StoreFixture.identifier(42)

  init() throws {
    fixture = try StoreFixture()
  }

  private var folder: String {
    StoreFixture.folder(identifier)
  }

  private func sealWithAttachment(
    content: String,
    declaredSize: Int? = nil,
  ) throws -> String {
    let blobDigest = fixture.digest(of: content)
    let result = StoreSamples.recordedResult().setting(
      "attachments",
      """
      [{"name":"log.txt","blob":"uc-blob-v1-sha256:\(blobDigest)",\
      "size_bytes":\(declaredSize ?? content.utf8.count)}]
      """,
    )
    try fixture.sealRun(
      identifier,
      results: [result],
      blobs: [blobDigest: content],
    )

    return blobDigest
  }

  @Test
  func `a damaged attachment is reported and the verdict stands`() throws {
    let blobDigest = try sealWithAttachment(content: "all good\n")
    try fixture.write(
      "\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))",
      "tampered",
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.results.first?.verdict == .pass)
    #expect(history.findings.map(\.description) == [
      "attachment 'log.txt' of \(StoreSamples.useCase) \(StoreSamples.route) in run " +
        "\(identifier) is damaged: the blob is 8 bytes, not 9",
    ])
  }

  @Test
  func `an attachment with the right size and the wrong bytes is damaged`() throws {
    let blobDigest = try sealWithAttachment(content: "all good\n")
    try fixture.write(
      "\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))",
      "all gone\n",
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.findings.map(\.description).first?.hasSuffix(
      "is damaged: the blob is not the bytes its digest names",
    ) == true)
  }

  @Test
  func `a missing attachment is damaged`() throws {
    let blobDigest = try sealWithAttachment(content: "all good\n")
    try FileManager.default.removeItem(
      at: fixture.directory.location(
        of: "\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))",
      ),
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(try history.findings == [
      .attachmentDamaged(
        run: RunIdentifier(validating: identifier),
        useCase: UseCaseIdentifier(validating: StoreSamples.useCase),
        route: RouteIdentifier(validating: StoreSamples.route),
        name: "log.txt",
        damage: .missing,
      ),
    ])
  }

  @Test
  func `an attachment that is a symlink is not followed`() throws {
    let blobDigest = try sealWithAttachment(content: "all good\n")
    let path = "\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))"
    try fixture.write("\(folder)/elsewhere", "all good\n")
    try FileManager.default.removeItem(at: fixture.directory.location(of: path))
    try fixture.directory.symlink(path, to: "../../../elsewhere")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.findings.map(\.description).first?.hasSuffix("the blob cannot be read") == true)
  }

  @Test
  func `a damaged attachment's text says damaged`() throws {
    let blobDigest = try sealWithAttachment(content: "all good\n")
    try fixture.write("\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))", "x")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    let descriptions = history.findings.map(\.description)
    #expect(descriptions.contains { text in
      text.contains("is damaged")
    })
  }

  @Test
  func `a report that changed after sealing is reported beside the verdicts`() throws {
    try fixture.sealRun(
      identifier,
      reports: ["auth-tests/auth-tests.jsonl": "{}\n"],
    )
    try fixture.write("\(folder)/reports/auth-tests/auth-tests.jsonl", "{}\n{}\n")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.first?.results.count == 1)
    #expect(history.findings.map(\.description) == [
      "run \(identifier): report auth-tests/auth-tests.jsonl changed after it was read",
    ])
  }

  @Test
  func `a report that has gone is reported beside the verdicts`() throws {
    try fixture.sealRun(
      identifier,
      reports: ["auth-tests/auth-tests.jsonl": "{}\n"],
    )
    try FileManager.default.removeItem(
      at: fixture.directory.location(of: "\(folder)/reports/auth-tests/auth-tests.jsonl"),
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
    #expect(history.findings.map(\.description) == [
      "run \(identifier): report auth-tests/auth-tests.jsonl is missing",
    ])
  }

  @Test
  func `reports and attachments that are intact give no findings`() throws {
    try fixture.sealRun(
      identifier,
      reports: ["a/one.xml": "<x/>", "b/two.xml": "<y/>"],
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.findings.isEmpty)
  }

  @Test
  func `a report written after sealing that the marker does not list is reported`() throws {
    try fixture.sealRun(
      identifier,
      reports: ["a/one.xml": "<x/>"],
    )
    try fixture.write("\(folder)/reports/late/report.xml", "<late/>")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
    #expect(history.findings.map(\.description) == [
      "run \(identifier): report late/report.xml was added after the run was sealed",
    ])
  }

  @Test
  func `a record run with a report added after sealing is reported`() throws {
    try fixture.sealRun(identifier)
    try fixture.write("\(folder)/reports/late.xml", "<late/>")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(try history.findings == [
      .reportAdded(
        run: RunIdentifier(validating: identifier),
        path: "late.xml",
      ),
    ])
  }
}
