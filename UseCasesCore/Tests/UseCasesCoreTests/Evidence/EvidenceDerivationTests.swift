import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Assurance, freshness, performed runs and matrix links, against the values
/// the TypeScript returned for the same inputs.
struct EvidenceDerivationTests {
  @Test
  func `assurance is derived exactly as the TypeScript derives it`() throws {
    let cases = try #require(EvidenceFixtures.section("assurance").arrayValue)
    #expect(cases.count == 11)
    for testCase in cases {
      let input = try #require(testCase["input"])
      let derived = EvidenceAssurance.derive(EvidenceAssuranceInput(
        kind: input["kind"] ?? .null,
        origin: input["origin"],
        captureMethod: input["captureMethod"],
        executionMethod: input["executionMethod"],
        exitStatus: input["exitStatus"]?.numberValue,
        digestComputedByTool: input["digestComputedByTool"]?.boolValue,
      ))
      #expect(
        EvidenceFixtures.wire(.object(derived)) == EvidenceFixtures.wire(testCase["output"]),
        "input \(EvidenceFixtures.wire(input))",
      )
    }
  }

  @Test
  func `freshness is evaluated exactly as the TypeScript evaluates it`() throws {
    let cases = try #require(EvidenceFixtures.section("freshness").arrayValue)
    #expect(cases.count == 9)
    for testCase in cases {
      let input = try #require(testCase["input"])
      let policy = input["policy"]?["semanticHashMismatch"]?.stringValue
        .flatMap(EvidenceHashMismatchPolicy.init(rawValue:))
      let result = EvidenceAssurance.evaluateFreshness(EvidenceFreshnessInput(
        explicitInvalidation: input["explicitInvalidation"]?.boolValue,
        semanticHashMatches: input["semanticHashMatches"]?.boolValue,
        semanticHashMismatchPolicy: policy,
      ))
      #expect(
        EvidenceFixtures.wire(result.jsonValue) == EvidenceFixtures.wire(testCase["output"]),
        "input \(EvidenceFixtures.wire(input))",
      )
    }
  }

  @Test
  func `performed runs are collected exactly as the TypeScript collects them`() throws {
    let section = try EvidenceFixtures.section("performed_runs")
    let workspace = try UseCasesFixtures.Workspace(tree: section["tree"])
    let snapshot = try EvidenceReplay.replay(context: workspace.context())
    let hashes = try #require(section["hashes"]?.arrayValue).map { pair in
      (pair.arrayValue?.first?.stringValue ?? "", pair.arrayValue?.last?.stringValue ?? "")
    }

    let runs = PerformedRuns.collect(snapshot: snapshot, currentSemanticHashes: hashes)

    #expect(EvidenceFixtures.wire(.array(runs.map(\.jsonValue))) == EvidenceFixtures
      .wire(section["runs"]))
    #expect(runs.map(\.rowIdentifier) == [
      "row.B",
      "row.a",
      "row.mixed",
      "row.primitive",
      "row.verdict",
      "row.z",
    ])
  }

  @Test(arguments: EvidenceGoldenCorpus.linkCaseNames)
  func `evidence links to the matrix exactly as the TypeScript links it`(caseName: String) throws {
    let testCase = try EvidenceFixtures.goldenCase(caseName, in: "links")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()
    let evidence = try EvidenceReplay.replay(context: context)
    let matrix = try UseCaseMatrixLoader.load(
      context: context,
      registry: UseCasesFixtures.registry.get(),
    )

    let links = EvidenceMatrixLinker.link(evidence: evidence, matrix: matrix)

    #expect(matrix.isComplete == (testCase["matrix_complete"] == .bool(true)))
    #expect(
      EvidenceFixtures.wire(.array(links.map(\.jsonValue)))
        == workspace.detokenized(EvidenceFixtures.wire(testCase["links"])),
    )
  }
}

/// `new Date(ms).toISOString()` and the event id built from the clock and the
/// random bytes.
struct EvidenceTimestampTests {
  @Test
  func `timestamps are spelled as toISOString spells them, extended years included`() throws {
    let cases = try #require(EvidenceFixtures.section("iso_dates").arrayValue)
    #expect(cases.count == 10)
    for testCase in cases {
      let milliseconds = try #require(testCase["milliseconds"]?.numberValue)
      #expect(JavaScriptTimestamp.isoString(milliseconds: milliseconds) == testCase["text"]?
        .stringValue)
    }
  }

  @Test(arguments: [
    (0.0, "00000000000000000000", "00000000-0000-7000-8000-000000000000"),
    (1_767_323_045_678, "0123456789abcdef0123", "019b7ca9-8f2e-7012-8345-6789abcdef01"),
    (8_640_000_000_000_000, "ffffffffffffffffffff", "1eb208c2-dc00-7fff-8fff-ffffffffffff"),
  ])
  func `an event id is uuidv7 laid out from the clock and 18 random hex digits`(
    milliseconds: Double,
    randomHex: String,
    identifier: String,
  ) {
    let bytes = EvidenceFixtures.FixedRandomSource(hexadecimal: randomHex).bytes
    #expect(EvidenceEventIdentifier
      .make(milliseconds: milliseconds, randomBytes: bytes) == identifier)
  }
}

/// `durableWrite.ts`: fsync, forgiving EIO/EINVAL/ENOSYS/ENOTSUP only inside
/// the OS temporary directory.
struct DurableWriteTests {
  @Test(arguments: [
    (["TMPDIR": "/custom/tmp/"], "/custom/tmp"),
    (["TMPDIR": "/"], "/"),
    (["TMP": "/from/tmp"], "/from/tmp"),
    (["TEMP": "/from/temp"], "/from/temp"),
    (["TMPDIR": "", "TMP": "/second"], "/second"),
    ([:], "/tmp"),
  ])
  func `the temporary directory is node's os tmpdir`(
    environment: [String: String],
    expected: String,
  ) {
    #expect(NodeOperatingSystem.temporaryDirectory(environment: environment) == expected)
  }

  @Test
  func `a best-effort code is forgiven only inside the temporary directory`() throws {
    let temporary = try TemporaryDirectory()
    let root = WorkspaceFixture.realPath(temporary.url.path)

    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EINVAL,
      path: root + "/a.jsonl",
      temporaryDirectory: root,
    ))
    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EIO,
      path: root,
      temporaryDirectory: root,
    ))
    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: ENOSYS,
      path: root + "/x",
      temporaryDirectory: root,
    ))
    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: ENOTSUP,
      path: root + "/x",
      temporaryDirectory: root,
    ))
    #expect(!DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EBADF,
      path: root + "/x",
      temporaryDirectory: root,
    ))
    #expect(!DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EINVAL,
      path: "/usr/x",
      temporaryDirectory: root,
    ))
    #expect(!DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EINVAL,
      path: root + "-sibling/x",
      temporaryDirectory: root,
    ))
  }

  @Test
  func `paths are compared after resolving symlinks, falling back to the path as written`() throws {
    let temporary = try TemporaryDirectory()
    let root = WorkspaceFixture.realPath(temporary.url.path)
    try FileManager.default.createDirectory(
      atPath: root + "/real",
      withIntermediateDirectories: true,
    )
    try FileManager.default.createSymbolicLink(
      atPath: root + "/link",
      withDestinationPath: root + "/real",
    )

    // Measured in node: an existing path resolves through the symlink and is
    // inside; a missing one cannot be realpath'd, falls back as written, and
    // is not.
    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EIO,
      path: root + "/link",
      temporaryDirectory: root + "/real",
    ))
    #expect(!DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EIO,
      path: root + "/link/file",
      temporaryDirectory: root + "/real",
    ))
    let currentDirectory = FileManager.default.currentDirectoryPath
    #expect(DurableWrite.isBestEffortTemporarySyncFailure(
      errorNumber: EIO,
      path: "not-there-at-all",
      temporaryDirectory: currentDirectory,
    ))
  }

  /// `fsync` on a pipe fails with EINVAL on macOS: a real failure, no mock.
  @Test
  func `a pipe's EINVAL is forgiven inside the temporary directory and raised outside it`() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(pipe(&descriptors) == 0)
    defer {
      close(descriptors[0])
      close(descriptors[1])
    }
    // An existing file under the temporary directory, as a ledger being
    // synced always is: a missing one would not resolve through `/var`.
    let temporary = try TemporaryDirectory()
    let inside = try temporary.writeFile("x.jsonl", contents: "").path
    #expect(inside
      .hasPrefix(NodeOperatingSystem
        .temporaryDirectory(environment: ProcessInfo.processInfo.environment)))

    #expect(throws: Never.self) {
      try DurableWrite.synchronizeBestEffortForTemporary(descriptor: descriptors[1], path: inside)
    }
    #expect(throws: FileAccessError(errorNumber: EINVAL, operation: "fsync", path: nil)) {
      try DurableWrite.synchronizeBestEffortForTemporary(
        descriptor: descriptors[1],
        path: "/usr/x.jsonl",
      )
    }
  }
}
