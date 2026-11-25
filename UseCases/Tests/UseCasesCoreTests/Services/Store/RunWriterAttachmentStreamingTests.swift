import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterAttachmentStreamingTests {
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

  private func attachments(of run: OpenRun) -> URL {
    fixture.directory.location(of: ".use-cases/runs/\(run.identifier.text)/attachments")
  }

  /// Every name below the attachments folder of a run that is not a folder.
  private func files(of run: OpenRun) throws -> [String] {
    let root = attachments(of: run)
    let enumerator = FileManager.default.enumerator(atPath: root.path)
    var found: [String] = []

    while let path = enumerator?.nextObject() as? String {
      var isFolder: ObjCBool = false
      _ = FileManager.default.fileExists(
        atPath: root.appendingPathComponent(path).path,
        isDirectory: &isFolder,
      )

      if !isFolder.boolValue {
        found.append(path)
      }
    }

    return found.sorted()
  }

  private func blob(
    _ run: OpenRun,
    _ digest: String,
  ) -> URL {
    fixture.directory.location(
      of: ".use-cases/runs/\(run.identifier.text)/\(StoreLayout.attachmentPath(digest: digest))",
    )
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a file is copied in chunks, digested and measured as it goes, at every size`(
    size: Int,
  ) throws {
    let bytes = ChunkSamples.bytes(count: size)
    let run = try open()

    let descriptors = try fixture.writer.ingest(
      [
        AttachmentSource(
          name: "evidence.bin",
          chunks: BufferedChunkReader(bytes: bytes),
        ),
      ],
      into: run,
    )

    let digest = hasher.sha256Hex(of: bytes)
    #expect(
      descriptors == [
        ResultAttachment(
          name: "evidence.bin",
          digest: digest,
          sizeBytes: size,
          mediaType: MediaTypeTable.mediaType(forFileNamed: "evidence.bin"),
        ),
      ],
    )
    #expect(try Array(Data(contentsOf: blob(run, digest))) == bytes)
    #expect(
      try files(of: run) == [String(StoreLayout.attachmentPath(digest: digest).dropFirst(12))],
    )
  }

  @Test
  func `the size kept is the bytes that were copied, whatever the file said its size was`() throws {
    let run = try open()
    let copied = Array("copied bytes".utf8)

    let descriptors = try fixture.writer.ingest(
      [
        AttachmentSource(
          name: "grown.txt",
          chunks: ScriptedChunkReader(
            chunks: [copied],
            length: 3,
          ),
        ),
      ],
      into: run,
    )

    #expect(descriptors.first?.sizeBytes == copied.count)
    #expect(descriptors.first?.digest == hasher.sha256Hex(of: copied))
  }

  @Test
  func `bytes held are kept as the same bytes read from a file are`() throws {
    let bytes = ChunkSamples.bytes(count: 70000)
    let run = try open()

    let held = try fixture.writer.ingest(
      [AttachmentFile(name: "a.bin", bytes: bytes)],
      into: run,
    )
    let streamed = try fixture.writer.ingest(
      [AttachmentSource(name: "a.bin", chunks: BufferedChunkReader(bytes: bytes))],
      into: run,
    )

    #expect(held == streamed)
  }

  @Test
  func `the same bytes under two names are one blob, and no copy is left beside it`() throws {
    let bytes = ChunkSamples.bytes(count: 100_000)
    let run = try open()

    let descriptors = try fixture.writer.ingest(
      [
        AttachmentSource(name: "one.bin", chunks: BufferedChunkReader(bytes: bytes)),
        AttachmentSource(name: "two.bin", chunks: BufferedChunkReader(bytes: bytes)),
      ],
      into: run,
    )

    #expect(Set(descriptors.map(\.digest)).count == 1)
    #expect(try files(of: run).count == 1)
  }

  @Test
  func `a file that cannot be read to its end keeps nothing and leaves nothing`() throws {
    let run = try open()
    let gone = URL(fileURLWithPath: "/gone")
    let source = AttachmentSource(
      name: "broken.bin",
      chunks: ScriptedChunkReader(
        chunks: [ChunkSamples.bytes(count: 65536), ChunkSamples.bytes(count: 100)],
        failure: .unreadable(gone, reason: "input/output error"),
      ),
    )

    #expect(throws: StoreWritingError.self) {
      _ = try fixture.writer.ingest([source], into: run)
    }
    #expect(try files(of: run).isEmpty)
  }

  @Test
  func `files of 50 MB are copied in chunks and kept under the digest of what was copied`() throws {
    let large = fixture.directory.location(of: "large.txt")
    try ChunkSamples.writeLargeFile(
      megabytes: 50,
      to: large,
    )
    let log = ChunkLog()
    let run = try open()
    var expected = hasher.accumulator()
    let block = ChunkSamples.text(count: 1 << 20)

    for _ in 0 ..< 50 {
      expected.add(block)
    }

    let descriptors = try fixture.writer.ingest(
      [
        AttachmentSource(
          name: "large.txt",
          chunks: AccountingChunkReader(
            PosixChunkReader(opening: large),
            log: log,
          ),
        ),
      ],
      into: run,
    )

    let kept = blob(run, expected.hex())
    let size = try FileManager.default.attributesOfItem(atPath: kept.path)[.size] as? Int
    #expect(descriptors.first?.digest == expected.hex())
    #expect(descriptors.first?.sizeBytes == 50 << 20)
    #expect(size == 50 << 20)
    #expect(log.largestChunk <= 65536)
    #expect(log.streamedBytes == 50 << 20)
    #expect(try files(of: run).count == 1)
  }
}
