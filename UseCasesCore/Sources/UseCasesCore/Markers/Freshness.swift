/// The freshness state machine (freshness.ts, spec sections 6, 7, 10.2): loaded
/// rows, the materialized registry, the current scan and the trusted proof
/// events in; one status per row, the policy gate, a summary and an honest
/// acceptance claim out.
///
/// Pure: no clock (the timestamp is injected), no filesystem, no git.
public enum Freshness {
  public static func derive(_ input: FreshnessInput) throws(CodeUnitCanonicalJSONError)
    -> FreshnessStatus
  {
    let index = FreshnessIndex(input)
    var rows: [FreshnessRow] = []
    var integrity = index.globalIntegrity
    var tally = FreshnessTally()
    for rowIdentifier in index.rowIdentifiers {
      let derivation = try FreshnessRowDerivation(
        rowIdentifier: rowIdentifier,
        index: index,
        input: input,
      )
      rows.append(derivation.row)
      integrity += derivation.integrity
      tally.count(derivation.row)
    }
    // guard_ok is a policy-block check and says nothing about proof; the
    // acceptance claim answers that.
    let guardOk = tally.summary.invalid == 0 && index.globalIntegrity.isEmpty
    return FreshnessStatus(
      generatedAt: input.generatedAt,
      tool: input.tool ?? ProductVersion.versionInfo(),
      productRoot: input.productRoot ?? ".",
      policyMode: input.policyMode,
      guardOk: guardOk,
      acceptanceClaim: tally.acceptanceClaim(total: rows.count, guardOk: guardOk),
      summary: tally.summary,
      integrityErrors: integrity,
      rows: rows,
    )
  }
}

/// The summary counts and the proven rows, each tallied once at its strongest
/// tier.
private struct FreshnessTally {
  var summary = FreshnessSummary()
  var proven = 0
  var byEvidence = EvidenceTally()

  mutating func count(_ row: FreshnessRow) {
    countStatus(row)
    let localStatus = row.localTier?.status
    countLocalStatus(localStatus)
    let performedRun = row.performedRun == true
    if performedRun {
      summary.performedRun += 1
    }
    guard row.status == .fresh || localStatus == .verifiedLocal || performedRun else {
      return
    }
    proven += 1
    if row.status == .fresh {
      byEvidence.signedProof += 1
    } else if localStatus == .verifiedLocal {
      byEvidence.localRun += 1
    } else {
      byEvidence.performedRun += 1
    }
  }

  private mutating func countStatus(_ row: FreshnessRow) {
    switch row.status {
    case .fresh: summary.fresh += 1
    case .suspect: summary.suspect += 1
    case .unproven: summary.unproven += 1
    case .unbound: summary.unbound += 1
    case .invalid: summary.invalid += 1
    }
    if row.policyBlock {
      summary.policyBlocked += 1
    }
  }

  private mutating func countLocalStatus(_ localStatus: LocalStatus?) {
    switch localStatus {
    case .verifiedLocal: summary.verifiedLocal += 1
    case .staleLocal: summary.staleLocal += 1
    case .unverifiedLocal: summary.unverifiedLocal += 1
    case .unattestedLocal: summary.unattestedLocal += 1
    case nil: break
    }
  }

  /// Claimable only when every row is proven by some tier and nothing blocks.
  func acceptanceClaim(
    total: Int,
    guardOk: Bool,
  ) -> AcceptanceClaim {
    let claimable = total > 0 && proven == total && guardOk
    // `statement` keeps its exact 0.5.5 wording: the upgrade contract allows
    // no observable change.
    let verdict = claimable ? "SUPPORTED" : "NOT_SUPPORTED"
    var parts = [
      "\(byEvidence.signedProof) signed proof",
      "\(byEvidence.localRun) local verifier run",
      "\(byEvidence.performedRun) performed run",
    ]
    if summary.unattestedLocal > 0 {
      parts.append("\(summary.unattestedLocal) unattested (run `uc verify`)")
    }
    return AcceptanceClaim(
      proven: proven,
      total: total,
      claimable: claimable,
      statement: "\(verdict) — \(proven) of \(total) behaviours verified",
      basis: parts.joined(separator: ", "),
      byEvidence: byEvidence,
      unattested: summary.unattestedLocal,
    )
  }
}
