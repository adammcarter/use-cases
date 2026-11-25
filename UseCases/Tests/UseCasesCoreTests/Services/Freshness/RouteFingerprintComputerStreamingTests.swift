import Foundation
import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerStreamingTests {
  private func fixture(resources: [String]) throws -> FreshnessFixture {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("config", file: "config/app.yml")],
        resources: resources,
      ),
    )
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    try fixture.write("config/app.yml", "a: 1\n")

    return fixture
  }

  private func fingerprints(
    of fixture: FreshnessFixture,
    over fileSystem: some FileSystemReading,
  ) throws -> RouteFingerprints {
    try fixture.fingerprints(using: RouteFingerprintComputer(fileSystem: fileSystem))
  }

  @Test(arguments: ChunkSamples.sizes, ["\n", "\r\n"])
  func `a resource read in chunks gives the fingerprint and the file digest of its bytes`(
    size: Int,
    lineEnding: String,
  ) throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        resources: [FreshnessSamples.file("fixtures/data.txt")],
      ),
    )
    let bytes = ChunkSamples.text(count: size, lineEnding: lineEnding)
    try fixture.workspace.directory.write(
      "fixtures/data.txt",
      bytes: bytes,
    )
    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          resources: [
            ResourceContribution(
              file: WorkspacePath(validating: "fixtures/data.txt"),
              content: ContentReferencer(policy: .standard).reference(of: bytes),
            ),
          ],
        ),
      ),
    )

    let streamed = try fingerprints(of: fixture, over: LocalFileSystem())

    #expect(!streamed.isInvalid, "problems: \(streamed.problems)")
    #expect(
      streamed.fingerprint(useCase: FreshnessSamples.useCase, route: "unit-tests") == expected,
    )
    #expect(
      streamed.fileDigests == [
        FileDigest(path: "fixtures/data.txt", digest: SHA256Hasher().sha256Hex(of: bytes)),
      ],
    )
  }

  @Test(arguments: ChunkSamples.sizes, ["\n", "\r\n"])
  func `a resource read in chunks gives the fingerprints and file digests of one read whole`(
    size: Int,
    lineEnding: String,
  ) throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/data.txt")])
    try fixture.workspace.directory.write(
      "fixtures/data.txt",
      bytes: ChunkSamples.text(count: size, lineEnding: lineEnding),
    )

    let streamed = try fingerprints(of: fixture, over: LocalFileSystem())
    let whole = try fingerprints(of: fixture, over: WholeFileSystem())

    #expect(!streamed.isInvalid, "problems: \(streamed.problems)")
    #expect(streamed == whole)
    #expect(streamed.fileDigests.map(\.path).contains("fixtures/data.txt"))
  }

  @Test
  func `a resource that is not text gives the same fingerprints read in chunks or whole`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/data.bin")])
    try fixture.workspace.directory.write(
      "fixtures/data.bin",
      bytes: ChunkSamples.bytes(count: 200_000) + [0xFF, 0x0D, 0x0A],
    )

    #expect(
      try fingerprints(of: fixture, over: LocalFileSystem())
        == fingerprints(of: fixture, over: WholeFileSystem()),
    )
  }

  @Test
  func `a resource that is only a resource is never read whole, and a linked one is read once`()
    throws
  {
    let fixture = try fixture(
      resources: [
        FreshnessSamples.file("fixtures/data.txt"),
        FreshnessSamples.file("config/app.yml"),
      ],
    )
    try fixture.workspace.directory.write(
      "fixtures/data.txt",
      bytes: ChunkSamples.text(count: 300_000),
    )
    let log = ChunkLog()

    let result = try fingerprints(
      of: fixture,
      over: ChunkAccountingFileSystem(log: log),
    )

    #expect(!result.isInvalid, "problems: \(result.problems)")
    #expect(log.openedCount == 1)
    #expect(log.largestChunk <= 65536)
    #expect(log.streamedBytes == 300_000)
    #expect(log.wholeReadCount == 2)
  }

  @Test
  func `a resource of 50 MB is read in chunks and its fingerprint is that of the file`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/large.txt")])
    let large = fixture.workspace.directory.location(of: "fixtures/large.txt")
    try FileManager.default.createDirectory(
      at: large.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try ChunkSamples.writeLargeFile(
      megabytes: 50,
      to: large,
    )
    let log = ChunkLog()

    let streamed = try fingerprints(
      of: fixture,
      over: ChunkAccountingFileSystem(log: log),
    )
    let whole = try fingerprints(of: fixture, over: WholeFileSystem())

    #expect(!streamed.isInvalid, "problems: \(streamed.problems)")
    #expect(streamed == whole)
    #expect(log.largestChunk <= 65536)
    #expect(log.streamedBytes == 50 << 20)
    #expect(log.openedCount == 1)
  }

  @Test
  func `a resource that normalization changes is read twice, in chunks both times`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/crlf.txt")])
    try fixture.workspace.directory.write(
      "fixtures/crlf.txt",
      bytes: ChunkSamples.text(count: 1000, lineEnding: "\r\n"),
    )
    let log = ChunkLog()

    _ = try fingerprints(
      of: fixture,
      over: ChunkAccountingFileSystem(log: log),
    )

    #expect(log.openedCount == 2)
    #expect(log.streamedBytes == 2000)
  }
}
