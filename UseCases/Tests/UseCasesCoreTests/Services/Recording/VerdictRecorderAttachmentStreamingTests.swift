import Foundation
import Testing
@testable import UseCasesCore

struct VerdictRecorderAttachmentStreamingTests {
  private let freshness: FreshnessFixture
  private let evidence: TemporaryDirectory
  private let log = ChunkLog()
  private let hasher = SHA256Hasher()

  init() throws {
    freshness = try FreshnessFixture()
    evidence = try TemporaryDirectory()
  }

  private func recorder() -> VerdictRecorder {
    let clock = FixedTimekeeper()

    return VerdictRecorder(
      fingerprinter: RouteFingerprintComputer(),
      writing: Result { () throws(StoreSchemaLoadingError) in
        try RunWriter(
          clock: clock,
          random: FixedRandomBits(),
        )
      },
      reader: AccountingAttachmentReader(log: log),
      clock: clock,
    )
  }

  private func planned(
    _ recorder: VerdictRecorder,
    attaching files: [String],
  ) throws -> RecordPlan {
    let loaded = try freshness.workspace.loaded()

    return try recorder.plan(
      RecordRequest(
        useCase: "app.toggle",
        route: "manual",
        status: "pass",
        message: nil,
        attachments: files.map(evidence.location(of:)),
      ),
      in: loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  @Test(arguments: ChunkSamples.sizes)
  func `an attachment of any size is kept as the file was when the request was checked`(
    size: Int,
  ) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try evidence.write("log.bin", bytes: bytes)
    let recorder = recorder()
    let plan = try planned(recorder, attaching: ["log.bin"])
    try evidence.write("log.bin", bytes: [1, 2, 3])

    let run = try recorder.commit(plan)

    let digest = hasher.sha256Hex(of: bytes)
    let kept = try #require(run.attachments.first)
    let blob = freshness.workspace.directory.location(
      of: ".use-cases/runs/\(run.runIdentifier)/\(StoreLayout.attachmentPath(digest: digest))",
    )
    #expect(kept.blob == "uc-blob-v1-sha256:\(digest)")
    #expect(kept.sizeBytes == size)
    #expect(try Array(Data(contentsOf: blob)) == bytes)
  }

  @Test
  func `an attachment of 50 MB is never held whole, from the check to the run`() throws {
    let large = evidence.location(of: "large.log")
    try ChunkSamples.writeLargeFile(
      megabytes: 50,
      to: large,
    )
    let recorder = recorder()

    let plan = try planned(recorder, attaching: ["large.log"])
    let run = try recorder.commit(plan)

    #expect(run.attachments.first?.sizeBytes == 50 << 20)
    #expect(log.largestChunk <= 65536)
    // Once to keep it as it was, and once to keep it in the run.
    #expect(log.streamedBytes == 2 * (50 << 20))
  }

  @Test
  func `checking attachments reads nothing of them`() throws {
    try evidence.write("log.txt", "kept")

    try recorder().checkAttachments(at: [evidence.location(of: "log.txt")])

    #expect(log.openedCount == 1)
    #expect(log.streamedBytes == 0)
  }

  @Test
  func `the copy a request holds is gone with the request`() throws {
    try evidence.write("log.txt", "kept")
    var plan: RecordPlan? = try planned(recorder(), attaching: ["log.txt"])
    let copy = try #require(plan?.result.attachments.files.first?.file)

    #expect(FileManager.default.fileExists(atPath: copy.path))

    plan = nil
    #expect(!FileManager.default.fileExists(atPath: copy.path))
  }
}
