import Foundation
import Testing

/// The black-box oracle for lifecycle/signals.yml, row
/// `verify_preserves_other_rows`.
struct LifecycleVerifyPreservesTests {
  // golden_single_row. The incremental loop the docs recommend has to be safe:
  // verifying one row must not cost another row its evidence.
  @Test
  func `verifying one row leaves every other row's evidence intact`() async throws {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    _ = try await SignalsMultiRow.verifyAll(workspace)
    let beta = try await SignalsMultiRow.rowStatus(workspace, "beta")
    #expect(beta?["local_status"]?.stringValue == "VERIFIED_LOCAL")

    _ = try await SignalsMultiRow.verifyRow(workspace, "alpha")
    let betaAfter = try await SignalsMultiRow.rowStatus(workspace, "beta")
    #expect(
      betaAfter?["local_status"]?.stringValue == "VERIFIED_LOCAL",
      "a row the run did not target must keep its evidence",
    )
    let alphaAfter = try await SignalsMultiRow.rowStatus(workspace, "alpha")
    #expect(alphaAfter?["local_status"]?.stringValue == "VERIFIED_LOCAL")
  }

  // golden_replaces_prior_record. Re-verifying replaces, it does not accrete —
  // otherwise the ledger would grow a record per run and readers would have to
  // guess which one is current.
  @Test
  func `re-verifying a row replaces its prior record rather than duplicating`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    _ = try await SignalsMultiRow.verifyAll(workspace)
    #expect(try SignalsWorkspace.ledgerLineCount(workspace) == 2)

    _ = try await SignalsMultiRow.verifyRow(workspace, "alpha")
    #expect(
      try SignalsWorkspace.ledgerLineCount(workspace) == 2,
      "one record per row, not one per run",
    )
  }

  // bad_retained_evidence_is_rechecked. Preserving a record is not the same as
  // trusting it: a row whose code moved is demoted, not left falsely green.
  @Test
  func `retained evidence is still re-checked, so a changed row goes STALE`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    _ = try await SignalsMultiRow.verifyAll(workspace)
    let beta = try await SignalsMultiRow.rowStatus(workspace, "beta")
    #expect(beta?["local_status"]?.stringValue == "VERIFIED_LOCAL")

    // Change beta's bound code INSIDE its span, without re-verifying it.
    // Rewriting the whole file would delete the markers bind inserted and make
    // the row UNBOUND, which measures something else entirely.
    let source = try workspace.directory.readFile("src/beta.ts")
    try workspace.directory.writeFile(
      "src/beta.ts",
      contents: source.replacingOccurrences(of: "return 1;", with: "return 2;"),
    )
    _ = try await SignalsMultiRow.verifyRow(workspace, "alpha")

    let betaAfter = try await SignalsMultiRow.rowStatus(workspace, "beta")
    #expect(
      betaAfter?["local_status"]?.stringValue == "STALE_LOCAL",
      "a row whose code changed must be demoted rather than kept green",
    )
  }

  // edge_no_targets. A run that matches nothing must write nothing away.
  @Test
  func `verifying an UNBOUND row targets nothing and leaves the ledger intact`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(
      .init(rows: ["alpha", "beta", "gamma"], bind: ["alpha", "beta"]),
    )
    _ = try await SignalsMultiRow.verifyAll(workspace)
    let before = try SignalsWorkspace.ledgerLineCount(workspace)

    let verified = try await SignalsMultiRow.verifyRow(workspace, "gamma")
    #expect(verified.isOk == true)
    let results = verified.data["results"]?.arrayValue ?? []
    #expect(results.isEmpty)
    #expect(
      try SignalsWorkspace.ledgerLineCount(workspace) == before,
      "a run that targeted nothing must write nothing away",
    )
  }
}

/// The black-box oracle for lifecycle/signals.yml, row
/// `acceptance_claim_is_honest`.
struct LifecycleAcceptanceClaimTests {
  // bad_nothing_proven. The field an agent quotes must say NOT_SUPPORTED while
  // nothing is proven, even though the policy guard is green — the guard is
  // only saying nothing is BLOCKING.
  @Test
  func `with nothing proven the claim is NOT_SUPPORTED though the guard is green`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.claimable(scanned) == false)
    let statement = scanned.at("acceptance_claim.statement")?.stringValue ?? ""
    #expect(statement.contains("NOT_SUPPORTED"))
    #expect(scanned.at("acceptance_claim.proven")?.intValue == 0)
  }

  // golden_all_proven. With every row proven the claim is claimable and names
  // how many behaviours back it.
  @Test
  func `with every row proven the claim is claimable and counts what backs it`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    _ = try await SignalsMultiRow.verifyAll(workspace)

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.claimable(scanned) == true)
    #expect(scanned.at("acceptance_claim.proven")?.intValue == 2)
    #expect(SignalsWorkspace.evidenceCount(scanned, "local_run") == 2)
  }

  // bad_unbound_row_blocks_the_claim. An UNBOUND row is never counted as
  // proven, so one unbound row is enough to stop the whole claim.
  @Test
  func `an unbound row is never counted as proven, so it blocks the claim`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(
      .init(rows: ["alpha", "beta", "gamma"], bind: ["alpha", "beta"]),
    )
    _ = try await SignalsMultiRow.verifyAll(workspace)

    let scanned = try await SignalsWorkspace.scan(workspace)
    let gamma = try await SignalsMultiRow.rowStatus(workspace, "gamma")
    #expect(gamma?["status"]?.stringValue == "UNBOUND")
    #expect(
      SignalsWorkspace.claimable(scanned) == false,
      "one unbound row blocks the claim",
    )
    #expect(scanned.at("acceptance_claim.proven")?.intValue == 2)
  }

  // edge_local_axis_counted_alongside_signed. A green KEYLESS matrix must not
  // read as a failing one just because nothing is signed.
  @Test
  func `the local axis is counted alongside the signed axis`() async throws {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    _ = try await SignalsMultiRow.verifyAll(workspace)

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(scanned.at("summary.verified_local")?.intValue == 2)
    #expect(
      scanned.at("summary.unproven")?.intValue == 2,
      "signed status stays UNPROVEN with no keys",
    )
    #expect(SignalsWorkspace.evidenceCount(scanned, "signed_proof") == 0)
    #expect(SignalsWorkspace.claimable(scanned) == true, "keyless green is still green")
  }
}
