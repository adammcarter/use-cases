import Foundation
import Testing
@testable import UseCasesCore

struct VerdictRecorderAttachmentTests {
  private let fixture: RecorderFixture
  private let evidence: TemporaryDirectory
  private let hasher = SHA256Hasher()

  init() throws {
    fixture = try RecorderFixture()
    evidence = try TemporaryDirectory()
  }

  private func record(
    _ files: [String],
    route: String = "manual",
  ) throws -> RecordedRun {
    let plan = try fixture.plan(
      "app.toggle",
      route,
      attachments: files.map(evidence.location(of:)),
    )

    return try fixture.recorder.commit(plan)
  }

  private func blob(
    _ run: RecordedRun,
    _ digest: String,
  ) throws -> [UInt8] {
    let path = ".use-cases/runs/\(run.runIdentifier)/\(StoreLayout.attachmentPath(digest: digest))"

    return try Array(Data(contentsOf: fixture.freshness.workspace.directory.location(of: path)))
  }

  // MARK: - Keeping

  @Test
  func `an attachment is kept by its content, with its name, size and media type`() throws {
    let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF]
    try evidence.write(
      "screen shot.PNG",
      bytes: bytes,
    )
    let digest = hasher.sha256Hex(of: bytes)

    let run = try record(["screen shot.PNG"])

    let kept = try #require(run.attachments.first)
    #expect(run.attachments.count == 1)
    #expect(kept.name == "screen shot.PNG")
    #expect(kept.blob == "uc-blob-v1-sha256:\(digest)")
    #expect(kept.sizeBytes == 6)
    #expect(kept.mediaType == "image/png")
    #expect(try blob(run, digest) == bytes)
  }

  @Test
  func `the result the reader finds names the attachment and nothing is damaged`() throws {
    try evidence.write(
      "log.txt",
      "all good\n",
    )

    let run = try record(["log.txt"])

    let stored = try #require(fixture.readHistory().runs.first)
    let attachment = try #require(stored.results.first?.detail?.attachments.first)
    #expect(attachment.name == "log.txt")
    #expect(attachment.digest == hasher.sha256Hex(of: Array("all good\n".utf8)))
    #expect(attachment.sizeBytes == 9)
    #expect(attachment.mediaType == "text/plain")
    #expect(stored.findings.isEmpty)
    #expect(stored.identifier.text == run.runIdentifier)
  }

  @Test
  func `a file whose ending is not in the table is kept with no media type`() throws {
    try evidence.write(
      "trace.out",
      "x",
    )

    let run = try record(["trace.out"])

    #expect(run.attachments.first?.mediaType == nil)
  }

  @Test
  func `the attachments are kept in the order they were given`() throws {
    try evidence.write(
      "b.txt",
      "2",
    )
    try evidence.write(
      "a.txt",
      "1",
    )
    try evidence.write(
      "c.log",
      "3",
    )

    let run = try record(["b.txt", "a.txt", "c.log"])

    #expect(run.attachments.map(\.name) == ["b.txt", "a.txt", "c.log"])
  }

  @Test
  func `an empty file is evidence too`() throws {
    try evidence.write(
      "empty.txt",
      bytes: [],
    )

    let run = try record(["empty.txt"])

    let kept = try #require(run.attachments.first)
    #expect(kept.sizeBytes == 0)
    #expect(try blob(run, hasher.sha256Hex(of: [])) == [])
  }

  @Test
  func `the same bytes under two names are two descriptors and one blob`() throws {
    try evidence.write(
      "one.txt",
      "same",
    )
    try evidence.write(
      "two.log",
      "same",
    )

    let run = try record(["one.txt", "two.log"])

    let digest = hasher.sha256Hex(of: Array("same".utf8))
    let shard = ".use-cases/runs/\(run.runIdentifier)/attachments/sha256/\(digest.prefix(2))"
    let names = try FileManager.default.contentsOfDirectory(
      atPath: fixture.freshness.workspace.directory.location(of: shard).path,
    )
    #expect(run.attachments.map(\.name) == ["one.txt", "two.log"])
    #expect(Set(run.attachments.map(\.blob)).count == 1)
    #expect(names == [String(digest.dropFirst(2))])
  }

  @Test
  func `the stored copy is the evidence: changing the file afterwards changes nothing`() throws {
    try evidence.write(
      "log.txt",
      "before",
    )
    let plan = try fixture.plan(
      "app.toggle",
      "manual",
      attachments: [evidence.location(of: "log.txt")],
    )
    try evidence.write(
      "log.txt",
      "after the plan",
    )

    let run = try fixture.recorder.commit(plan)

    let digest = hasher.sha256Hex(of: Array("before".utf8))
    #expect(run.attachments.first?.blob == "uc-blob-v1-sha256:\(digest)")
    #expect(try blob(run, digest) == Array("before".utf8))
  }

  @Test
  func `a run with no attachments has no attachments folder`() throws {
    let run = try record([])

    let folder = ".use-cases/runs/\(run.runIdentifier)"
    #expect(run.attachments.isEmpty)
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.freshness.workspace.directory.location(of: "\(folder)/attachments").path,
      ),
    )
  }

  @Test
  func `names that differ only in case are two names`() throws {
    try evidence.write(
      "a/Log.txt",
      "1",
    )
    try evidence.write(
      "b/log.txt",
      "2",
    )

    let run = try record(["a/Log.txt", "b/log.txt"])

    #expect(run.attachments.map(\.name) == ["Log.txt", "log.txt"])
  }

  // MARK: - Refusing

  @Test
  func `a file that is not there is refused, and nothing is written`() throws {
    let missing = evidence.location(of: "nope.png")

    #expect(throws: RecordingError.attachmentMissing(missing.path)) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [missing],
      )
    }
    #expect(!fixture.hasStore)
  }

  @Test
  func `a folder is refused`() throws {
    try evidence.makeDirectory("shots")
    let folder = evidence.location(of: "shots")

    #expect(throws: RecordingError.attachmentIsFolder(folder.path)) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [folder],
      )
    }
    #expect(!fixture.hasStore)
  }

  @Test
  func `a pipe is refused without being opened`() throws {
    try evidence.makeFIFO("pipe.log")
    let pipe = evidence.location(of: "pipe.log")

    #expect(throws: RecordingError.attachmentNotRegular(pipe.path)) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [pipe],
      )
    }
  }

  @Test
  func `two attachments with one display name are refused, whatever folders they are in`() throws {
    try evidence.write(
      "a/log.txt",
      "1",
    )
    try evidence.write(
      "b/log.txt",
      "2",
    )

    #expect(throws: RecordingError.duplicateAttachmentName("log.txt")) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [evidence.location(of: "a/log.txt"), evidence.location(of: "b/log.txt")],
      )
    }
    #expect(!fixture.hasStore)
  }

  @Test
  func `the same file twice is two attachments with one name`() throws {
    try evidence.write(
      "log.txt",
      "1",
    )
    let file = evidence.location(of: "log.txt")

    #expect(throws: RecordingError.duplicateAttachmentName("log.txt")) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [file, file],
      )
    }
  }

  @Test
  func `one bad attachment among good ones refuses them all`() throws {
    try evidence.write(
      "good.txt",
      "1",
    )
    let missing = evidence.location(of: "bad.txt")

    #expect(throws: RecordingError.attachmentMissing(missing.path)) {
      try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [evidence.location(of: "good.txt"), missing],
      )
    }
    #expect(!fixture.hasStore)
  }

  @Test(.enabled(if: getuid() != 0, "root can read any file"))
  func `a file that cannot be read is refused with the system's reason`() throws {
    try evidence.write(
      "secret.txt",
      "x",
    )
    let file = evidence.location(of: "secret.txt")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000],
      ofItemAtPath: file.path,
    )

    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: file.path,
      )
    }

    do {
      _ = try fixture.plan(
        "app.toggle",
        "manual",
        attachments: [file],
      )
      Issue.record("the request was planned")
    } catch let error as RecordingError {
      guard case let .attachmentUnreadable(path, _) = error else {
        Issue.record("not unreadable: \(error)")
        return
      }

      #expect(path == file.path)
    } catch {
      Issue.record("not a recording error: \(error)")
    }

    #expect(!fixture.hasStore)
  }

  @Test
  func `the checks agree with planning: a request that is refused there is refused here`() throws {
    let missing = evidence.location(of: "nope.png")

    #expect(throws: RecordingError.attachmentMissing(missing.path)) {
      try fixture.recorder.checkAttachments(at: [missing])
    }
    #expect(!fixture.hasStore)
  }

  @Test
  func `a route that is not there is told before an attachment that is not`() throws {
    let missing = evidence.location(of: "nope.png")

    #expect(throws: RecordingError.noRoute(useCase: "app.toggle", route: "nope")) {
      try fixture.plan(
        "app.toggle",
        "nope",
        attachments: [missing],
      )
    }
  }
}
