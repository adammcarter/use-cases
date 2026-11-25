import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterAttachmentTests {
  private let fixture: WriterFixture
  private let hasher = SHA256Hasher()

  init() throws {
    fixture = try WriterFixture()
  }

  private func open() throws -> OpenRun {
    try fixture.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )
  }

  private func folder(_ run: OpenRun) -> String {
    ".use-cases/runs/\(run.identifier.text)"
  }

  private func result(_ attachments: [ResultAttachment]) -> StoredResult {
    StoredResult(
      useCase: .sample(StoreSamples.useCase),
      route: .sample(StoreSamples.route),
      fingerprint: .sample("a"),
      verdict: .pass,
      detail: StoredResultDetail(
        recordedAt: StoreSamples.timestamp,
        origin: .recorded,
        message: nil,
        attachments: attachments,
      ),
    )
  }

  @Test
  func `ingested bytes are published under their digest and described`() throws {
    let run = try open()
    let bytes = Array("evidence".utf8)

    let descriptors = try fixture.writer.ingest(
      [AttachmentFile(name: "notes.md", bytes: bytes)],
      into: run,
    )

    let digest = hasher.sha256Hex(of: bytes)
    #expect(
      descriptors == [
        ResultAttachment(
          name: "notes.md",
          digest: digest,
          sizeBytes: 8,
          mediaType: "text/markdown",
        ),
      ],
    )
    #expect(
      try fixture.read("\(folder(run))/\(StoreLayout.attachmentPath(digest: digest))")
        == "evidence",
    )
  }

  @Test
  func `no folder is made for nothing to ingest`() throws {
    let run = try open()

    let descriptors = try fixture.writer.ingest(
      [],
      into: run,
    )

    #expect(descriptors.isEmpty)
    #expect(fixture.names(in: folder(run)) == ["results.jsonl", "run.json"])
  }

  @Test
  func `bytes that are already there are not written again`() throws {
    let run = try open()
    let source = AttachmentFile(
      name: "a.txt",
      bytes: Array("same".utf8),
    )

    let first = try fixture.writer.ingest(
      [source],
      into: run,
    )
    let second = try fixture.writer.ingest(
      [AttachmentFile(name: "b.txt", bytes: source.bytes)],
      into: run,
    )

    #expect(first.first?.digest == second.first?.digest)
    #expect(fixture.names(in: "\(folder(run))/attachments/sha256").count == 1)
  }

  @Test
  func `a sealed run takes no more evidence`() throws {
    let run = try fixture.recordRun()

    #expect(throws: StoreWritingError.sealed(run.identifier)) {
      try fixture.writer.ingest(
        [AttachmentFile(name: "late.txt", bytes: [1])],
        into: run,
      )
    }
  }

  @Test
  func `a run is sealed over ingested evidence and the reader finds it intact`() throws {
    let run = try open()
    let descriptors = try fixture.writer.ingest(
      [AttachmentFile(name: "a.txt", bytes: [1, 2, 3])],
      into: run,
    )

    try fixture.writer.append(
      result(descriptors),
      to: run,
    )
    _ = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    let stored = try #require(fixture.readHistory().runs.first)
    #expect(stored.findings.isEmpty)
    #expect(stored.results.first?.detail?.attachments == descriptors)
  }

  @Test
  func `a result that names a blob that was never ingested cannot be sealed over`() throws {
    let run = try open()
    let missing = ResultAttachment(
      name: "ghost.txt",
      digest: String(repeating: "a", count: 64),
      sizeBytes: 3,
      mediaType: nil,
    )

    try fixture.writer.append(
      result([missing]),
      to: run,
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
    #expect(!fixture.names(in: folder(run)).contains("completion.json"))
  }

  @Test
  func `a blob whose bytes are not the ones it names cannot be sealed over`() throws {
    let run = try open()
    let descriptors = try fixture.writer.ingest(
      [AttachmentFile(name: "a.txt", bytes: [1, 2, 3])],
      into: run,
    )
    let digest = try #require(descriptors.first?.digest)
    let blob = fixture.directory.location(
      of: "\(folder(run))/\(StoreLayout.attachmentPath(digest: digest))",
    )
    try FileManager.default.removeItem(at: blob)
    try Data([9, 9, 9]).write(to: blob)

    try fixture.writer.append(
      result(descriptors),
      to: run,
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
  }
}
