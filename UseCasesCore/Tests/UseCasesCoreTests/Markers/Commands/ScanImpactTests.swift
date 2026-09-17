import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// scan, impact and the precommit decision replayed over real workspaces and
/// real git repositories, each result compared as bytes with what the
/// TypeScript produced for the same steps.
struct ScanImpactTests {
  private typealias Fixtures = ScanImpactFixtures
  private typealias Commands = MarkerCommandsFixtures

  @Test(arguments: ScanImpactGoldenCorpus.scanCaseNames)
  func `each scan step returns what the TypeScript returned`(caseName: String) throws {
    try replay(caseName, section: "scan_cases") { step, options, root in
      let context = try Fixtures.context(options, root: root)
      let scanOptions = try Fixtures.scanOptions(options, context: context, root: root)
      let registry = try Commands.registry.get()
      let result: ScanCommandResult
      do throws(MarkerCommandError) {
        result = try ScanCommand.run(
          scanOptions,
          registry: registry,
          runKeyLocation: Fixtures.emptyRunKeyLocation(root),
        )
      } catch {
        Fixtures.expectSameBytes(
          Fixtures.wire(Fixtures.thrown(error), root: root),
          Fixtures.wire(step["thrown"], root: "<ROOT>"),
          "\(caseName) thrown",
        )
        return
      }
      Fixtures.expectSameBytes(
        Fixtures.wire(result.jsonValue, root: root),
        Fixtures.wire(step["result"], root: "<ROOT>"),
        "\(caseName) result",
      )
      let precommit = try Precommit.decide(
        validateLedger: PrecommitInputDecoding
          .ledger(#require(Fixtures.root()["validate_ledger_ok"])),
        scan: PrecommitScanInput(result),
      )
      Fixtures.expectSameBytes(
        Fixtures.wire(precommit.jsonValue, root: root),
        Fixtures.wire(step["precommit"], root: "<ROOT>"),
        "\(caseName) precommit",
      )
      Fixtures.expectSameBytes(
        Precommit.pullRequestSummary(result.status).replacingOccurrences(of: root, with: "<ROOT>"),
        step["pr_summary"]?.stringValue,
        "\(caseName) PR summary",
      )
    }
  }

  @Test(arguments: ScanImpactGoldenCorpus.impactCaseNames)
  func `each impact step returns what the TypeScript returned`(caseName: String) throws {
    try replay(caseName, section: "impact_cases") { step, options, root in
      let context = try Fixtures.context(options, root: root)
      let result = try ImpactCommand.run(
        Fixtures.impactOptions(options, context: context),
        registry: Commands.registry.get(),
        runKeyLocation: Fixtures.emptyRunKeyLocation(root),
      )
      Fixtures.expectSameBytes(
        Fixtures.wire(result.jsonValue, root: root),
        Commands.wire(step["result"]),
        "\(caseName) result",
      )
    }
  }

  @Test(arguments: ScanImpactGoldenCorpus.precommitCaseNames)
  func `each precommit decision and summary is what the TypeScript produced`(
    caseName: String,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: "precommit_cases")
    let scanSlice = try #require(entry["scan"])
    let scan = try PrecommitInputDecoding.scan(scanSlice)
    // The decoder writes back exactly what it read, so nothing precommit reads
    // was lost on the way in.
    Fixtures.expectSameBytes(
      Commands.wire(scan.status.jsonValue),
      Commands.wire(scanSlice["status"]),
      "\(caseName) decoded status",
    )

    let result = try Precommit.decide(
      validateLedger: PrecommitInputDecoding.ledger(#require(entry["validate_ledger"])),
      scan: scan,
    )
    Fixtures.expectSameBytes(
      Fixtures.wire(result.jsonValue, root: "<ROOT>"),
      Fixtures.wire(entry["output"], root: "<ROOT>"),
      "\(caseName) decision",
    )
    Fixtures.expectSameBytes(
      Precommit.pullRequestSummary(scan.status),
      entry["pr_summary"]?.stringValue,
      "\(caseName) PR summary",
    )
  }

  /// Build the case's entries under a fresh root, then run its steps in order.
  private func replay(
    _ caseName: String,
    section: String,
    command: (JSONValue, JSONValue, String) throws -> Void,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: section)
    let (directory, root) = try Commands.temporaryRoot()
    let steps = try #require(entry["steps"]?.arrayValue)
    defer {
      Commands.restorePermissions(Fixtures.chmodEntries(steps), under: root)
      _ = directory
    }
    let entries = try #require(entry["entries"]?.arrayValue)
    #expect(!Commands.wire(.array(entries)).contains("<ROOT>"), "entries never name the root")
    try Commands.materialize(entries, under: root)
    for step in steps where try !Fixtures.applyWorkspaceStep(step, root: root) {
      try command(step, step["options"] ?? .object(JSONObject()), root)
    }
  }
}
