import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The two chain behaviours no corpus case reaches: a chain break as the ONLY
/// fault, and a legacy proof minted before the chain existed.
///
/// `EvidenceLedgerTests` pins the chain verifier against hand-written ledgers and
/// `MarkerCommandsTests` pins `validate-ledger` over a ledger that is wrong in
/// several ways at once — so nothing shows a broken chain, by itself, deciding
/// the command's exit code, and nothing shows an un-chained proof still proving
/// its row.
struct LedgerChainRulesTests {
  private typealias Fixtures = VerifyProveFixtures

  @Test
  func `a broken chain alone fails validate-ledger with exit four`() throws {
    let ledger = try ChainedLedger()

    try ledger.rewrite { events in
      var edited = try #require(events[1].objectValue)
      edited["created_at"] = .string("2026-06-28T23:59:59.000Z")
      return try [events[0], .object(ProofSignature.sign(
        edited,
        privateKeyPEM: Fixtures.string("private_key_pem"),
        keyIdentifier: Fixtures.string("key_id"),
      )), events[2]]
    }

    let result = try ledger.validate()

    #expect(result.exitCode == 4)
    #expect(result.isOK == false)
    #expect(result.chainValid == false)
    // The chain is the ONLY fault: the registry is untouched and every
    // signature still verifies, because the edited entry was re-signed.
    #expect(result.registryValid)
    #expect(result.errors.map(\.code) == ["UCM_LEDGER_CHAIN_BROKEN"])
  }

  @Test
  func `an untouched chained ledger validates with every entry verified`() throws {
    let ledger = try ChainedLedger()

    let result = try ledger.validate()

    #expect(result.exitCode == 0)
    #expect(result.isOK)
    #expect(result.chainValid)
    #expect(result.chainVerifiedEntries == 3)
    #expect(result.chainLegacyPrefixCount == 0)
    #expect(result.errors.isEmpty)
  }

  @Test
  func `a legacy proof carrying no chain fields still validates and proves its row`() throws {
    let ledger = try ChainedLedger()

    try ledger.rewrite { events in
      try events.map { event in
        var stripped = try #require(event.objectValue)
        stripped["entry_index"] = nil
        stripped["previous_entry_hash"] = nil
        return try .object(ProofSignature.sign(
          stripped,
          privateKeyPEM: Fixtures.string("private_key_pem"),
          keyIdentifier: Fixtures.string("key_id"),
        ))
      }
    }

    let result = try ledger.validate()
    let statuses = try ledger.scannedRowStatuses()

    #expect(result.exitCode == 0)
    #expect(result.chainValid)
    #expect(result.chainVerifiedEntries == 0)
    #expect(result.chainLegacyPrefixCount == 3)
    #expect(statuses.contains(.fresh), "a legacy proof still proves its row: \(statuses)")
  }
}

/// The corpus's three-event chained ledger, built by running its own prove steps
/// over a real workspace, then available for tampering.
private struct ChainedLedger {
  private typealias Fixtures = VerifyProveFixtures

  let materialized: MaterializedCase
  let context: ResolvedWorkspaceContext

  var evidencePath: String {
    NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl")
  }

  var bindingsPath: String {
    NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl")
  }

  init() throws {
    materialized = try Fixtures.materialized(
      "trusted_append_chains_signs_and_skips_fresh",
      in: "prove_cases",
    )
    context = try Fixtures.context(root: materialized.root)
    for step in materialized.steps {
      let options = try #require(step["options"])
      _ = try ProveCommand.run(
        Fixtures.proveOptions(options, context: context, root: materialized.root),
        registry: MarkerCommandsFixtures.registry.get(),
        runKeyLocation: Fixtures.runKeyLocation(options, root: materialized.root),
        environment: [:],
      )
    }
    try #require(Fixtures.proofEvents(materialized.root).count == 3)
  }

  /// Replace the ledger with whatever `transform` makes of its events.
  func rewrite(_ transform: ([JSONValue]) throws -> [JSONValue]) throws {
    let events = try Fixtures.proofEvents(materialized.root).map(\.value)
    let replaced = try transform(events)
    let text = replaced.map { event in
      JSONWriter.encode(event)
    }.joined(separator: "\n") + "\n"
    try NodeFile.writeText(text, atPath: evidencePath)
  }

  func validate() throws -> ValidateLedgerCommandResult {
    try ValidateLedgerCommand.run(
      ValidateLedgerCommandOptions(
        context: context,
        evidencePath: evidencePath,
        bindingsPath: bindingsPath,
        publicKeyResolver: Fixtures.publicKeyResolver(),
      ),
      registry: MarkerCommandsFixtures.registry.get(),
    )
  }

  func scannedRowStatuses() throws -> [RowStatus] {
    var options = try ScanCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: bindingsPath,
      evidencePath: evidencePath,
      policyMode: .feature,
      publicKeyResolver: Fixtures.publicKeyResolver(),
      generatedAt: Fixtures.string("generated_at"),
    )
    options.repositoryWorkingDirectory = context.workspaceRoot
    return try ScanCommand.run(
      options,
      registry: MarkerCommandsFixtures.registry.get(),
      runKeyLocation: Fixtures.runKeyLocation(.object(JSONObject()), root: materialized.root),
    ).status.rows.map(\.status)
  }
}
