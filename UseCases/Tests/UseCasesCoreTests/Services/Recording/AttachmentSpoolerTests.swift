import Foundation
import Testing
@testable import UseCasesCore

struct AttachmentSpoolerTests {
  private let spooler = AttachmentSpooler()
  private let hasher = SHA256Hasher()

  private func source(
    _ name: String,
    _ bytes: [UInt8],
  ) -> AttachmentSource {
    AttachmentSource(
      name: name,
      chunks: BufferedChunkReader(bytes: bytes),
    )
  }

  @Test(arguments: ChunkSamples.sizes)
  func `an attachment is kept as it is, with its digest and size`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)

    let spooled = try spooler.spool([source("evidence.bin", bytes)])

    let kept = try #require(spooled.files.first)
    #expect(spooled.files.count == 1)
    #expect(kept.name == "evidence.bin")
    #expect(kept.digest == hasher.sha256Hex(of: bytes))
    #expect(kept.length == size)
    #expect(try Array(Data(contentsOf: kept.file)) == bytes)
  }

  @Test
  func `attachments are kept in the order given, each in a file of its own`() throws {
    let spooled = try spooler.spool(
      [
        source("one.txt", Array("one".utf8)),
        source("two.txt", Array("two".utf8)),
        source("three.txt", Array("one".utf8)),
      ],
    )

    #expect(spooled.files.map(\.name) == ["one.txt", "two.txt", "three.txt"])
    #expect(Set(spooled.files.map(\.file)).count == 3)
    #expect(spooled.files[0].digest == spooled.files[2].digest)
  }

  @Test
  func `nothing to keep is no folder`() throws {
    #expect(try spooler.spool([]) == .none)
  }

  @Test
  func `the copies stay while any plan holds them`() throws {
    var plans: [SpooledAttachments] = []
    let kept: URL

    do {
      let spooled = try spooler.spool([source("a.txt", Array("a".utf8))])

      kept = try #require(spooled.files.first?.file)
      plans = [spooled, spooled]
    }

    plans.removeLast()
    #expect(FileManager.default.fileExists(atPath: kept.path))

    plans.removeLast()
    #expect(!FileManager.default.fileExists(atPath: kept.path))
  }

  @Test
  func `the copies are gone once nothing holds them`() throws {
    let location: URL

    do {
      let spooled = try spooler.spool([source("a.txt", Array("a".utf8))])
      location = try #require(spooled.files.first?.file)

      #expect(FileManager.default.fileExists(atPath: location.path))
    }

    #expect(!FileManager.default.fileExists(atPath: location.path))
  }

  @Test
  func `a failure part way leaves nothing behind`() throws {
    let files = FolderNotingFileWriter()
    let broken = AttachmentSource(
      name: "broken.bin",
      chunks: ScriptedChunkReader(
        chunks: [Array("first".utf8)],
        failure: .unreadable(URL(fileURLWithPath: "/gone"), reason: "input/output error"),
      ),
    )

    #expect(throws: StoreWritingError.self) {
      try AttachmentSpooler(files: files).spool([source("fine.txt", Array("fine".utf8)), broken])
    }

    let folder = try #require(files.folders.first)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test
  func `an attachment of 50 MB is kept in chunks`() throws {
    let directory = try TemporaryDirectory()
    let large = directory.location(of: "large.txt")
    try ChunkSamples.writeLargeFile(
      megabytes: 50,
      to: large,
    )
    let log = ChunkLog()

    let spooled = try spooler.spool(
      [
        AttachmentSource(
          name: "large.txt",
          chunks: AccountingChunkReader(
            PosixChunkReader(opening: large),
            log: log,
          ),
        ),
      ],
    )

    let kept = try #require(spooled.files.first)
    let size = try FileManager.default.attributesOfItem(atPath: kept.file.path)[.size] as? Int
    #expect(kept.length == 50 << 20)
    #expect(size == 50 << 20)
    #expect(log.largestChunk <= 65536)
    #expect(log.streamedBytes == 50 << 20)
  }
}
