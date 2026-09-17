import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The pieces of `scan` a corpus case reaches only in combination: the exit
/// code ladder rung by rung, the run key's default location, and the bridge
/// from evidence performed runs to freshness input.
struct ScanRulesTests {
  private typealias Fixtures = ScanImpactFixtures
  private typealias Commands = MarkerCommandsFixtures

  /// One exit-code combination: the ledgers' validity, whether the summary
  /// counts an INVALID row, whether an INVALID row is policy-blocked, and
  /// whether a non-INVALID row is.
  struct ExitCodeCase: CustomTestStringConvertible, Sendable {
    let registryValid: Bool
    let evidenceValid: Bool
    let invalidCounted: Bool
    let invalidRowBlocked: Bool
    let validRowBlocked: Bool
    let expected: Int

    var testDescription: String {
      "registry \(registryValid) evidence \(evidenceValid) invalid-counted \(invalidCounted) "
        + "invalid-blocked \(invalidRowBlocked) valid-blocked \(validRowBlocked) -> \(expected)"
    }
  }

  static let exitCodeCases: [ExitCodeCase] = [
    ExitCodeCase(true, true, false, false, false, 0),
    ExitCodeCase(true, true, false, true, false, 0),
    ExitCodeCase(true, true, false, false, true, 1),
    ExitCodeCase(true, true, false, true, true, 1),
    ExitCodeCase(true, true, true, false, false, 3),
    ExitCodeCase(true, true, true, true, false, 3),
    ExitCodeCase(true, true, true, false, true, 3),
    ExitCodeCase(false, true, false, false, false, 4),
    ExitCodeCase(true, false, false, false, false, 4),
    ExitCodeCase(false, false, false, false, false, 4),
    ExitCodeCase(false, true, true, true, true, 4),
    ExitCodeCase(true, false, true, false, false, 4),
    ExitCodeCase(true, false, false, false, true, 4),
  ]

  @Test(arguments: exitCodeCases)
  func `the exit code ladder is 4 then 3 then 1 then 0`(testCase: ExitCodeCase) throws {
    let base = try unboundStatus()
    var rows = base.rows
    var summary = base.summary
    if testCase.invalidCounted {
      summary.invalid = 1
    }
    if testCase.invalidRowBlocked {
      rows[0] = rewrite(rows[0], status: .invalid, policyBlock: true)
    }
    if testCase.validRowBlocked {
      rows[1] = rewrite(rows[1], status: .unproven, policyBlock: true)
    }
    let status = FreshnessStatus(
      generatedAt: base.generatedAt,
      tool: base.tool,
      productRoot: base.productRoot,
      policyMode: base.policyMode,
      guardOk: base.guardOk,
      acceptanceClaim: base.acceptanceClaim,
      summary: summary,
      integrityErrors: base.integrityErrors,
      rows: rows,
    )
    #expect(ScanGate.exitCode(
      status,
      registryValid: testCase.registryValid,
      evidenceValid: testCase.evidenceValid,
    ) == testCase.expected)
  }

  @Test
  func `with no run key path the key is read from the home directory or the override`() throws {
    let entry = try Fixtures.entry("bound_and_verified_reads_verified_local", in: "scan_cases")
    let (directory, root) = try Commands.temporaryRoot()
    defer {
      _ = directory
    }
    try Commands.materialize(#require(entry["entries"]?.arrayValue), under: root)
    let expected = try #require(entry["steps"]?.arrayValue?.first)["result"]
    let context = try Fixtures.context(.object(JSONObject()), root: root)
    var options = try Fixtures.scanOptions(.object(JSONObject()), context: context, root: root)
    options.runKeyPath = nil
    let registry = try Commands.registry.get()

    let fromHome = try ScanCommand.run(
      options,
      registry: registry,
      runKeyLocation: RunKeyLocation(environment: [:], homeDirectory: root + "/home"),
    )
    Fixtures.expectSameBytes(
      Fixtures.wire(fromHome.jsonValue, root: root),
      Commands.wire(expected),
      "fromHome",
    )

    let fromOverride = try ScanCommand.run(
      options,
      registry: registry,
      runKeyLocation: RunKeyLocation(
        environment: ["UC_RUN_KEY_FILE": " \(root)/home/.use-cases/run-key "],
        homeDirectory: root + "/no-home",
      ),
    )
    Fixtures.expectSameBytes(
      Fixtures.wire(fromOverride.jsonValue, root: root),
      Commands.wire(expected),
      "fromOverride",
    )

    let fromNowhere = try ScanCommand.run(
      options,
      registry: registry,
      runKeyLocation: Fixtures.emptyRunKeyLocation(root),
    )
    #expect(fromNowhere.status.rows.map(\.localTier?.status) == [
      .unattestedLocal,
      .unattestedLocal,
    ])
  }

  @Test
  func `the process run key location reads HOME first`() {
    let environment = ProcessInfo.processInfo.environment
    #expect(RunKeyLocation.process.homeDirectory == environment["HOME"] ?? NSHomeDirectory())
  }

  @Test(arguments: [
    ([JSONValue.string("pnpm"), .string("test")], ["pnpm", "test"] as [String]?),
    ([JSONValue.string("pnpm"), .number(3), .null], nil),
  ])
  func `every performed run keeps its row and only an all-string argv`(
    argv: [JSONValue],
    expected: [String]?,
  ) {
    let runs = LocalVerificationResults.freshnessPerformedRuns([
      EvidencePerformedRun(rowIdentifier: "row.a", argv: argv),
      EvidencePerformedRun(rowIdentifier: "row.b", argv: []),
    ])
    #expect(runs == [
      PerformedRun(rowIdentifier: "row.a", argv: expected),
      PerformedRun(rowIdentifier: "row.b", argv: []),
    ])
  }

  private func unboundStatus() throws -> FreshnessStatus {
    let entry = try Fixtures.entry("unbound_rows", in: "scan_cases")
    let step = try #require(entry["steps"]?.arrayValue?.first)
    return try PrecommitInputDecoding.status(#require(step["result"]?["status"]))
  }

  private func rewrite(
    _ row: FreshnessRow,
    status: RowStatus,
    policyBlock: Bool,
  ) -> FreshnessRow {
    FreshnessRow(
      rowIdentifier: row.rowIdentifier,
      hashes: row.hashes,
      status: status,
      policyBlock: policyBlock,
      reasons: row.reasons,
      knownBindingSlugs: row.knownBindingSlugs,
      currentBindingSlugs: row.currentBindingSlugs,
      missingRegisteredBindingSlugs: row.missingRegisteredBindingSlugs,
      unregisteredCurrentBindingSlugs: row.unregisteredCurrentBindingSlugs,
      currentBindings: row.currentBindings,
      matchingProofEvent: row.matchingProofEvent,
      latestTrustedProofEvent: row.latestTrustedProofEvent,
      requiredAction: row.requiredAction,
      requiredForRelease: row.requiredForRelease,
      localTier: row.localTier,
      performedRun: row.performedRun,
      variantLocalStatus: row.variantLocalStatus,
      currentBindingSetHash: row.currentBindingSetHash,
    )
  }
}

extension ScanRulesTests.ExitCodeCase {
  init(
    _ registryValid: Bool,
    _ evidenceValid: Bool,
    _ invalidCounted: Bool,
    _ invalidRowBlocked: Bool,
    _ validRowBlocked: Bool,
    _ expected: Int,
  ) {
    self.init(
      registryValid: registryValid,
      evidenceValid: evidenceValid,
      invalidCounted: invalidCounted,
      invalidRowBlocked: invalidRowBlocked,
      validRowBlocked: validRowBlocked,
      expected: expected,
    )
  }
}
