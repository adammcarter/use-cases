/// One required row below the gate's bar, or one ungated row drifting below it.
public struct ScanGateOffender: Equatable, Sendable {
  public let rowIdentifier: String
  public let status: RowStatus
  /// Nil when the row carries no local tier; emitted as `null`.
  public let localStatus: LocalStatus?

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("status", .string(status.rawValue)),
      ("local_status", localStatus.map { status in
        .string(status.rawValue)
      } ?? .null),
    ]))
  }
}

/// The acceptable bar a gated row must meet.
public enum ScanGateBar: String, Equatable, Sendable {
  /// Release mode: a trusted signed proof.
  case fresh = "FRESH"
  /// Every other mode: the keyless local green light, or better.
  case verifiedLocal = "VERIFIED_LOCAL"
}

/// `scan --gate` (0.1.0): the opt-in exit-code gate's verdict.
public struct ScanGateResult: Equatable, Sendable {
  public let blocked: Bool
  public let policyMode: PolicyMode
  public let requiredBar: ScanGateBar
  public let offendingRows: [ScanGateOffender]
  /// Non-required rows below the bar and drifting (not UNBOUND): advisory
  /// only, surfaced so a passing gate never reads as endorsing them.
  public let ungatedBelowBar: [ScanGateOffender]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("blocked", .bool(blocked)),
      ("policy_mode", .string(policyMode.rawValue)),
      ("required_bar", .string(requiredBar.rawValue)),
      ("offending_rows", .array(offendingRows.map(\.jsonValue))),
      ("ungated_below_bar", .array(ungatedBelowBar.map(\.jsonValue))),
    ]))
  }
}

/// The gate and the exit-code ladder `scan` reports (scan.ts).
public enum ScanGate {
  /// `evaluateScanGate`: pure over an already-derived status. Only rows marked
  /// `required_for_release` block; release mode's bar is FRESH, every other
  /// mode's is VERIFIED_LOCAL (FRESH always clears it).
  public static func evaluate(
    _ status: FreshnessStatus,
    policyMode: PolicyMode,
  ) -> ScanGateResult {
    var offending: [ScanGateOffender] = []
    var ungatedBelowBar: [ScanGateOffender] = []
    for row in status.rows {
      let belowBar = !meetsBar(row, policyMode: policyMode)
      let offender = ScanGateOffender(
        rowIdentifier: row.rowIdentifier,
        status: row.status,
        localStatus: row.localTier?.status,
      )
      if row.requiredForRelease {
        if belowBar {
          offending.append(offender)
        }
        continue
      }
      if belowBar, row.status != .unbound {
        ungatedBelowBar.append(offender)
      }
    }
    return ScanGateResult(
      blocked: !offending.isEmpty,
      policyMode: policyMode,
      requiredBar: policyMode == .release ? .fresh : .verifiedLocal,
      offendingRows: offending,
      ungatedBelowBar: ungatedBelowBar,
    )
  }

  /// `scanExitCode` (spec 8.2): 4 when the registry or the evidence ledger is
  /// invalid; else 3 when any row is INVALID; else 1 when a non-INVALID row is
  /// policy-blocked; else 0.
  public static func exitCode(
    _ status: FreshnessStatus,
    registryValid: Bool,
    evidenceValid: Bool,
  ) -> Int {
    if !registryValid || !evidenceValid {
      return 4
    }
    if status.summary.invalid > 0 {
      return 3
    }
    if status.rows.contains(where: { row in
      row.policyBlock && row.status != .invalid
    }) {
      return 1
    }
    return 0
  }

  /// `rowMeetsGateBar`.
  private static func meetsBar(
    _ row: FreshnessRow,
    policyMode: PolicyMode,
  ) -> Bool {
    if row.status == .fresh {
      return true
    }
    if policyMode == .release {
      return false
    }
    return row.localTier?.status == .verifiedLocal
  }
}
