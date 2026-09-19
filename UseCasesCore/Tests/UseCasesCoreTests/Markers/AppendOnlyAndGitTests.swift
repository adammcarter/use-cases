import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The append-only line check, the `git show` base-ref read, and the
/// `git diff` parsing behind `use-cases impact` — the git parts run against a REAL
/// temporary repository, replayed step for step from the corpus.
struct AppendOnlyAndGitTests {
  @Test
  func `the append-only check agrees with the TypeScript`() throws {
    for entry in try MarkersLedgerFixtures.section("append_only") {
      let result = try AppendOnly.check(
        oldLines: MarkersLedgerFixtures.strings(entry, "old_lines"),
        newLines: MarkersLedgerFixtures.strings(entry, "new_lines"),
      )

      #expect(
        try MarkersLedgerFixtures.wire(result.jsonValue) == MarkersLedgerFixtures
          .wire(#require(entry["result"])),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `JSONL text splits into the TypeScript's lines`() throws {
    for entry in try MarkersLedgerFixtures.section("split_jsonl") {
      let text = try MarkersLedgerFixtures.string(entry, "text")

      #expect(try AppendOnly.splitJSONLines(text) == MarkersLedgerFixtures.strings(entry, "lines"))
    }
  }

  @Test
  func `name-status output parses to the TypeScript's changes`() throws {
    for entry in try MarkersLedgerFixtures.section("name_status") {
      let changes = try GitDiff.parseNameStatus(MarkersLedgerFixtures.string(entry, "text"))

      #expect(
        try MarkersLedgerFixtures.wire(.array(changes.map(\.jsonValue)))
          == MarkersLedgerFixtures.wire(#require(entry["changes"])),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `unified-zero hunks parse to the TypeScript's ranges`() throws {
    for entry in try MarkersLedgerFixtures.section("hunks") {
      let ranges = try GitDiff.parseUnifiedZeroHunks(MarkersLedgerFixtures.string(entry, "text"))

      #expect(
        try MarkersLedgerFixtures.wire(.array(ranges.map(\.jsonValue)))
          == MarkersLedgerFixtures.wire(#require(entry["ranges"])),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `ranges overlap exactly when they intersect`() throws {
    for entry in try MarkersLedgerFixtures.section("overlaps") {
      let firstBounds = entry["a"]?.arrayValue?.compactMap(\.numberValue)
      let secondBounds = entry["b"]?.arrayValue?.compactMap(\.numberValue)
      let first = try #require(firstBounds)
      let second = try #require(secondBounds)

      #expect(GitDiff.rangesOverlap(
        LineRange(startLine: Int(first[0]), endLine: Int(first[1])),
        LineRange(startLine: Int(second[0]), endLine: Int(second[1])),
      ) == entry["overlaps"]?.boolValue)
    }
  }

  /// Replays the corpus's git history into a fresh temporary repository.
  private func replayRepository() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory()
    for step in try #require(MarkersLedgerFixtures.root()["git_steps"]?.arrayValue) {
      let strings = step.arrayValue?.compactMap(\.stringValue)
      let parts = try #require(strings)
      if parts.first == "write" {
        try directory.writeFile(parts[1], contents: parts[2])
      } else {
        _ = try GitProcessRunner().run(
          Array(parts.dropFirst()),
          workingDirectory: directory.url.path,
        )
      }
    }
    return directory
  }

  @Test
  func `changed files are collected from a real repository as the TypeScript collected them`(
  ) throws {
    let repository = try replayRepository()

    for entry in try MarkersLedgerFixtures.section("collect_changed_files") {
      let diff = try GitDiff.collectChangedFiles(
        base: entry["base"]?.stringValue,
        staged: entry["staged"]?.boolValue ?? false,
        workingDirectory: repository.url.path,
      )

      #expect(
        try MarkersLedgerFixtures.wire(diff.jsonValue) == MarkersLedgerFixtures
          .wire(#require(entry["result"])),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `a base-ref file is read from a real repository as the TypeScript read it`() throws {
    let repository = try replayRepository()

    for entry in try MarkersLedgerFixtures.section("read_base_ref") {
      let reference = try MarkersLedgerFixtures.string(entry, "ref")
      let path = try MarkersLedgerFixtures.string(entry, "path")
      let expected = try #require(entry["result"])
      let name = entry["name"]?.stringValue ?? ""

      do throws(GitError) {
        let text = try AppendOnly.readBaseReferenceFile(
          baseReference: reference,
          path: path,
          workingDirectory: repository.url.path,
        )
        #expect(expected["value"]?.stringValue == text, "\(name)")
      } catch {
        #expect(expected["throws"]?.stringValue == error.message, "\(name)")
      }
    }
  }

  @Test
  func `the current ledger is checked against its base-ref version`() throws {
    let repository = try replayRepository()

    let appended = try AppendOnly.checkAgainstBaseReference(
      baseReference: "base",
      path: ".use-cases/proofs.jsonl",
      currentText: "{\"a\":1}\n{\"b\":2}\n",
      workingDirectory: repository.url.path,
    )
    let edited = try AppendOnly.checkAgainstBaseReference(
      baseReference: "base",
      path: ".use-cases/proofs.jsonl",
      currentText: "{\"a\":2}\n",
      workingDirectory: repository.url.path,
    )

    #expect(appended == .holds)
    #expect(MarkersLedgerFixtures.wire(edited.jsonValue).contains("\"kind\":\"edited\""))
  }

  /// node's `execFileSync` caps stdout at 1 MiB; one byte more fails the read
  /// with no stderr, which the TypeScript reports as "unknown error". Faithful,
  /// and a limit a large base-ref ledger will hit.
  @Test
  func `a base-ref file over one mebibyte fails as node's buffer limit fails`() throws {
    let repository = try TemporaryDirectory()
    let runner = GitProcessRunner()
    let path = repository.url.path
    _ = try runner.run(["init", "-q"], workingDirectory: path)
    try repository.writeFile("limit.jsonl", contents: String(repeating: "x", count: 1_048_576))
    try repository.writeFile("over.jsonl", contents: String(repeating: "x", count: 1_048_577))
    _ = try runner.run(["add", "-A"], workingDirectory: path)
    _ = try runner.run(
      [
        "-c",
        "user.name=U",
        "-c",
        "user.email=u@example.com",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-q",
        "-m",
        "big",
      ],
      workingDirectory: path,
    )

    let atLimit = try AppendOnly.readBaseReferenceFile(
      baseReference: "HEAD",
      path: "limit.jsonl",
      workingDirectory: path,
    )
    let error = #expect(throws: GitError.self) {
      try AppendOnly.readBaseReferenceFile(
        baseReference: "HEAD",
        path: "over.jsonl",
        workingDirectory: path,
      )
    }

    #expect(atLimit.utf8.count == 1_048_576)
    #expect(error?.message == "git show HEAD:over.jsonl failed: unknown error")
  }

  @Test
  func `git that cannot start is reported with node's spawn text`() {
    let error = #expect(throws: GitError.self) {
      try AppendOnly.readBaseReferenceFile(
        baseReference: "HEAD",
        path: "keep.swift",
        workingDirectory: "/nonexistent-use-cases-repository",
      )
    }

    #expect(error?.message == "git show HEAD:keep.swift failed: spawnSync git ENOENT")
  }
}
