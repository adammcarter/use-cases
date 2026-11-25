import Foundation
import Testing
@testable import UseCasesCore

struct ReportDigesterStreamingTests {
  private let directory: TemporaryDirectory
  private let hasher = SHA256Hasher()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func digester(over log: ChunkLog) -> ReportDigester {
    ReportDigester(
      access: StoreFileAccess(
        fileSystem: ChunkAccountingFileSystem(log: log),
        json: JSONReader(),
      ),
    )
  }

  private var reports: StoreFile {
    StoreFile(workspace: directory.url).appending("reports")
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a report is digested as its bytes are, whatever its size`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try directory.write(".use-cases/reports/unit/report.xml", bytes: bytes)

    let found = digester(over: ChunkLog()).digests(
      below: reports,
      prefix: "",
    )

    #expect(
      found == ReportDigests(
        digests: [FileDigest(path: "unit/report.xml", digest: hasher.sha256Hex(of: bytes))],
        unusable: [],
      ),
    )
  }

  @Test
  func `a report of 50 MB is digested in chunks and never read whole`() throws {
    let report = directory.location(of: ".use-cases/reports/big.xml")
    try FileManager.default.createDirectory(
      at: report.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try ChunkSamples.writeLargeFile(
      megabytes: 50,
      to: report,
    )
    let log = ChunkLog()
    var expected = hasher.accumulator()
    let block = ChunkSamples.text(count: 1 << 20)

    for _ in 0 ..< 50 {
      expected.add(block)
    }

    let found = digester(over: log).digests(
      below: reports,
      prefix: "",
    )

    #expect(found.digests == [FileDigest(path: "big.xml", digest: expected.hex())])
    #expect(found.unusable.isEmpty)
    #expect(log.wholeReadCount == 0)
    #expect(log.openedCount == 1)
    #expect(log.largestChunk <= 65536)
    #expect(log.streamedBytes == 50 << 20)
  }

  @Test
  func `a report that is a symlink is not digested, and is not followed`() throws {
    try directory.write("elsewhere.xml", "outside")
    try directory.makeDirectory(".use-cases/reports")
    try directory.symlink(".use-cases/reports/link.xml", to: "../../elsewhere.xml")
    let log = ChunkLog()

    let found = digester(over: log).digests(
      below: reports,
      prefix: "",
    )

    #expect(found.digests.isEmpty)
    #expect(found.unusable.map(\.path) == ["link.xml"])
    #expect(log.openedCount == 0)
  }
}
