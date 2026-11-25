import Foundation
import Testing
@testable import UseCasesCLI

struct RecordCommandAttachTests {
  private let workspace: LinksWorkspace
  private let evidence: TemporaryFolder

  init() throws {
    workspace = try LinksWorkspace()
    evidence = try TemporaryFolder()
  }

  private func path(_ name: String) -> String {
    evidence.url.appendingPathComponent(name).path
  }

  private func record(_ extra: [String]) async -> CommandResult {
    await workspace.run(
      ["--json", "record", "shop.pay.card", "unit-tests", "pass", "note", "--attach"] + extra,
    )
  }

  private func attachments(of result: CommandResult) throws -> [JSONValue] {
    guard
      case let .array(results)? = try result.document()["results"],
      case let .array(attachments)? = results.first?["attachments"]
    else {
      return []
    }

    return attachments
  }

  // MARK: - Keeping

  @Test
  func `the files given are kept with the verdict and told in the document`() async throws {
    try evidence.write("shot.PNG", "png bytes")
    try evidence.write("run.log", "line one\nline two\n")

    let result = await record([path("shot.PNG"), path("run.log")])

    let kept = try attachments(of: result)
    #expect(result.exitCode == 0)
    #expect(kept.count == 2)
    #expect(kept.first?["name"] == .string("shot.PNG"))
    #expect(kept.first?["size_bytes"] == .integer(9))
    #expect(kept.first?["media_type"] == .string("image/png"))
    #expect(kept.last?["name"] == .string("run.log"))
    #expect(kept.last?["media_type"] == .string("text/plain"))
  }

  @Test
  func `the blob is in the run under its digest, and the log names it`() async throws {
    try evidence.write("notes.txt", "kept")

    let result = await record([path("notes.txt")])

    let document = try result.document()
    guard
      case let .string(identifier)? = document["run_id"],
      case let .string(blob)? = try attachments(of: result).first?["blob"]
    else {
      Issue.record("no run id or blob")
      return
    }
    let digest = String(blob.dropFirst("uc-blob-v1-sha256:".count))
    let folder = ".use-cases/runs/\(identifier)"

    #expect(
      try workspace.read("\(folder)/attachments/sha256/\(digest.prefix(2))/\(digest.dropFirst(2))")
        == "kept",
    )
    #expect(try workspace.read("\(folder)/results.jsonl").contains(blob))
  }

  @Test
  func `a file with an ending that is not in the table has no media type member`() async throws {
    try evidence.write("trace.out", "x")

    let result = await record([path("trace.out")])

    let kept = try #require(attachments(of: result).first)
    #expect(kept["name"] == .string("trace.out"))
    #expect(kept["media_type"] == nil)
  }

  @Test
  func `a verdict with no attachments has no attachments member`() async throws {
    let result = await workspace.run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])

    guard case let .array(results)? = try result.document()["results"] else {
      Issue.record("no results")
      return
    }

    #expect(results.first?["attachments"] == nil)
  }

  @Test
  func `a relative path is read from where the command runs`() async throws {
    try workspace.folder.write("shots/home.md", "# home")

    let result = await record(["shots/home.md"])

    let kept = try #require(attachments(of: result).first)
    #expect(result.exitCode == 0)
    #expect(kept["name"] == .string("home.md"))
    #expect(kept["media_type"] == .string("text/markdown"))
  }

  @Test
  func `people are told the verdict in the same line as without attachments`() async throws {
    try evidence.write("a.txt", "x")

    let result = await workspace.run([
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
      "--attach",
      path("a.txt"),
      "--quiet",
    ])

    #expect(result.standardOutput == "recorded: shop.pay.card / unit-tests → pass\n")
  }

  // MARK: - Refusing

  @Test
  func `a file that is not there is a usage refusal that leaves nothing behind`() async throws {
    let result = await record([path("nope.png")])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains(path("nope.png")))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a folder is a usage refusal that leaves nothing behind`() async throws {
    try FileManager.default.createDirectory(
      at: evidence.url.appendingPathComponent("shots"),
      withIntermediateDirectories: true,
    )

    let result = await record([path("shots")])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `two attachments with one display name are a usage refusal`() async throws {
    try evidence.write("a/log.txt", "1")
    try evidence.write("b/log.txt", "2")

    let result = await record([path("a/log.txt"), path("b/log.txt")])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains("names must be unique"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `one bad file among good ones refuses the whole request`() async throws {
    try evidence.write("good.txt", "1")

    let result = await record([path("good.txt"), path("bad.txt")])

    #expect(result.exitCode == 2)
    #expect(!workspace.hasStore)
  }

  @Test
  func `a refusal of the verdict itself comes before one of the files`() async {
    let result = await workspace.run([
      "record",
      "shop.pay.card",
      "nope",
      "pass",
      "--attach",
      path("missing.png"),
    ])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no route"))
  }

  // MARK: - The schema

  @Test
  func `the document with attachments follows the published schema`() async throws {
    try evidence.write("shot.png", "x")
    try evidence.write("trace.out", "y")

    let result = await record([path("shot.png"), path("trace.out")])
    let schema = try PublishedSchema(path: "schemas/output/cli-record.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }
}
