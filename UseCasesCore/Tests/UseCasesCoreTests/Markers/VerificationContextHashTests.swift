import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The verification context hash embedded in every proof and re-derived at
/// scan time. A different byte here turns every FRESH row in an existing ledger
/// SUSPECT, so each hash is pinned to what the TypeScript computed.
struct VerificationContextHashTests {
  @Test(arguments: MarkersFreshnessGoldenCorpus.contextHashCaseNames)
  func `a row's context hash is the TypeScript's, byte for byte`(caseName: String) throws {
    let entry = try MarkersFreshnessFixtures.entry(caseName, in: "context_hash")
    let root = try MarkersFreshnessFixtures.string(entry, "root")
    let lockfile = entry["lockfile"]?.stringValue

    let hash = try VerificationContextHash.computeForRow(
      slug: MarkersFreshnessFixtures.string(entry, "slug"),
      verificationPolicy: MarkersFreshnessFixtures.policy(entry),
      rootDirectory: root,
      files: CorpusTextFiles(entry["files"]),
      lockfileName: lockfile,
      workspaceVerifiers: MarkersFreshnessFixtures.workspace(entry["workspace"]),
    )

    #expect(try hash == MarkersFreshnessFixtures.string(entry, "context_hash"))
  }

  /// Every path reads back as its own name, so this hash only matches when the
  /// Swift port read exactly the paths node read — joined and normalized as
  /// node joins them, absolute ones verbatim.
  @Test(arguments: MarkersFreshnessGoldenCorpus.contextHashCaseNames)
  func `the files read are the ones node read`(caseName: String) throws {
    let entry = try MarkersFreshnessFixtures.entry(caseName, in: "context_hash")

    let hash = try VerificationContextHash.computeForRow(
      slug: MarkersFreshnessFixtures.string(entry, "slug"),
      verificationPolicy: MarkersFreshnessFixtures.policy(entry),
      rootDirectory: MarkersFreshnessFixtures.string(entry, "root"),
      files: EchoTextFiles(),
      lockfileName: entry["lockfile"]?.stringValue,
      workspaceVerifiers: MarkersFreshnessFixtures.workspace(entry["workspace"]),
    )

    #expect(try hash == MarkersFreshnessFixtures.string(entry, "probe_hash"))
  }

  @Test
  func `a caller-built verifier list hashes as the TypeScript hashes it`() throws {
    for entry in try MarkersFreshnessFixtures.section("context_hash_direct") {
      let verifiers = try #require(entry["verifiers"]?.arrayValue).map(resolution)

      let hash = try VerificationContextHash.compute(
        verificationPolicy: entry["policy"],
        verifiers: verifiers,
        rootDirectory: "/repo",
        files: CorpusTextFiles(entry["files"]),
      )

      #expect(try hash == MarkersFreshnessFixtures.string(entry, "context_hash"))
    }
  }

  @Test
  func `a present, an absent and an empty lockfile give three different hashes`() throws {
    let hashes = try ["lockfile_present", "lockfile_absent", "lockfile_present_but_empty"]
      .map { caseName in
        let entry = try MarkersFreshnessFixtures.entry(caseName, in: "context_hash")
        return try VerificationContextHash.computeForRow(
          slug: MarkersFreshnessFixtures.string(entry, "slug"),
          verificationPolicy: MarkersFreshnessFixtures.policy(entry),
          rootDirectory: "/repo",
          files: CorpusTextFiles(entry["files"]),
          workspaceVerifiers: MarkersFreshnessFixtures.workspace(entry["workspace"]),
        )
      }

    #expect(Set(hashes).count == 3)
    #expect(VerificationContextHash.defaultLockfileName == "pnpm-lock.yaml")
    #expect(try VerificationContextHash.identifier
      == MarkersFreshnessFixtures.string(
        MarkersFreshnessFixtures.root(),
        "verification_context_hash_id",
      ))
  }

  @Test
  func `a declared input the disk cannot read as a file is raised, not hashed as absent`() throws {
    let directory = try TemporaryDirectory()
    _ = try directory.makeDirectory("Tests")
    let verifier = VerifierResolution.resolved(ResolvedVerifier(
      verifierIdentifier: "unit",
      source: .policy,
      evidenceKind: "test_result",
      command: [],
      inputs: ["Tests"],
      timeoutSeconds: nil,
      preset: nil,
    ))

    let error = #expect(throws: VerificationContextHashError.self) {
      try VerificationContextHash.compute(
        verificationPolicy: nil,
        verifiers: [verifier],
        rootDirectory: directory.url.path,
        files: LocalTextFiles(),
      )
    }

    #expect(error?.code == "EISDIR")
  }

  @Test
  func `the real filesystem reads the lockfile at the path the hash builds`() throws {
    let directory = try TemporaryDirectory()
    _ = try directory.writeFile("pnpm-lock.yaml", contents: "")
    let fake = CorpusTextFiles(.object(JSONObject([
      ("\(directory.url.path)/pnpm-lock.yaml", .string("")),
    ])))

    let onDisk = try VerificationContextHash.compute(
      verificationPolicy: nil,
      verifiers: [],
      rootDirectory: directory.url.path,
      files: LocalTextFiles(),
    )

    #expect(try onDisk == VerificationContextHash.compute(
      verificationPolicy: nil,
      verifiers: [],
      rootDirectory: directory.url.path,
      files: fake,
    ))
  }

  @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
  func `a non-finite timeout has no context hash`(timeout: Double) {
    let verifier = VerifierResolution.resolved(ResolvedVerifier(
      verifierIdentifier: "unit",
      source: .policy,
      evidenceKind: "test_result",
      command: [],
      inputs: [],
      timeoutSeconds: timeout,
      preset: nil,
    ))

    #expect(throws: VerificationContextHashError.nonFiniteNumber) {
      try VerificationContextHash.compute(
        verificationPolicy: nil,
        verifiers: [verifier],
        rootDirectory: "/repo",
        files: EchoTextFiles(),
      )
    }
  }

  private func resolution(_ value: JSONValue) throws -> VerifierResolution {
    let identifier = try MarkersFreshnessFixtures.string(value, "verifier_id")
    guard value["status"] == .string("resolved") else {
      return try .blocked(BlockedVerifier(
        verifierIdentifier: identifier,
        reason: MarkersFreshnessFixtures.string(value, "reason"),
      ))
    }
    return try .resolved(ResolvedVerifier(
      verifierIdentifier: identifier,
      source: #require(VerifierSource(rawValue: MarkersFreshnessFixtures.string(value, "source"))),
      evidenceKind: MarkersFreshnessFixtures.string(value, "evidence_kind"),
      command: MarkersFixtures.strings(value, "command"),
      inputs: MarkersFixtures.strings(value, "inputs"),
      timeoutSeconds: value["timeout_seconds"]?.numberValue,
      preset: value["preset"]?.stringValue.flatMap(VerifierPresetIdentifier.init(identifier:)),
    ))
  }
}
