public enum PrecommitDecision: String, Equatable, Sendable {
  case block = "BLOCK"
  case warn = "WARN"
  case clear = "OK"
}

public enum PrecommitSource: String, Equatable, Sendable {
  case validateLedger = "validate-ledger"
  case scan
}

public struct PrecommitBlockReason: Equatable, Sendable {
  public let source: PrecommitSource
  public let code: String
  /// Present only for a reason tied to one row.
  public let rowIdentifier: String?
  public let message: String

  var jsonValue: JSONValue {
    var object = JSONObject([("source", .string(source.rawValue)), ("code", .string(code))])
    object["row_id"] = rowIdentifier.map(JSONValue.string)
    object["message"] = .string(message)
    return .object(object)
  }
}

public struct PrecommitWarning: Equatable, Sendable {
  public let rowIdentifier: String
  public let status: RowStatus
  public let reason: String
  public let requiredAction: String
  /// The loud, multi-line warning block (spec 10.1).
  public let message: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("status", .string(status.rawValue)),
      ("reason", .string(reason)),
      ("required_action", .string(requiredAction)),
      ("message", .string(message)),
    ]))
  }
}

public struct PrecommitResult: Equatable, Sendable {
  public let decision: PrecommitDecision
  /// 1 when BLOCK, so the hook aborts; 0 otherwise.
  public let exitCode: Int
  public let blockReasons: [PrecommitBlockReason]
  public let warnings: [PrecommitWarning]
  /// Block reasons, then the loud warnings, ready to print.
  public let messages: [String]

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("decision", .string(decision.rawValue)),
      ("exit_code", .number(Double(exitCode))),
      ("block_reasons", .array(blockReasons.map(\.jsonValue))),
      ("warnings", .array(warnings.map(\.jsonValue))),
      ("messages", .array(messages.map(JSONValue.string))),
    ]))
  }
}

/// The slice of a validate-ledger result the precommit decision reads.
public struct PrecommitLedgerInput: Equatable, Sendable {
  public var isOK: Bool
  public var exitCode: Int
  public var evidenceValid: Bool
  public var registryValid: Bool
  public var appendOnly: Bool
  public var errors: [LedgerErrorReport]

  public init(
    isOK: Bool,
    exitCode: Int,
    evidenceValid: Bool,
    registryValid: Bool,
    appendOnly: Bool,
    errors: [LedgerErrorReport],
  ) {
    self.isOK = isOK
    self.exitCode = exitCode
    self.evidenceValid = evidenceValid
    self.registryValid = registryValid
    self.appendOnly = appendOnly
    self.errors = errors
  }

  public init(_ result: ValidateLedgerCommandResult) {
    self.init(
      isOK: result.isOK,
      exitCode: result.exitCode,
      evidenceValid: result.evidenceValid,
      registryValid: result.registryValid,
      appendOnly: result.appendOnly,
      errors: result.errors,
    )
  }
}

/// The slice of a scan result the precommit decision reads.
public struct PrecommitScanInput: Equatable, Sendable {
  public var exitCode: Int
  public var registryValid: Bool
  public var evidenceValid: Bool
  public var status: FreshnessStatus

  public init(
    exitCode: Int,
    registryValid: Bool,
    evidenceValid: Bool,
    status: FreshnessStatus,
  ) {
    self.exitCode = exitCode
    self.registryValid = registryValid
    self.evidenceValid = evidenceValid
    self.status = status
  }

  public init(_ result: ScanCommandResult) {
    self.init(
      exitCode: result.exitCode,
      registryValid: result.registryValid,
      evidenceValid: result.evidenceValid,
      status: result.status,
    )
  }
}

/// The precommit orchestrator and PR-summary formatter (precommit.ts, spec
/// 10.1 and 10.2). Pure: already-computed command results in, a decision or
/// text out.
public enum Precommit {
  /// `decidePrecommit`. BLOCK on a failed validate-ledger, a scan whose ledger
  /// or registry is invalid, a scan usage error (exit 2), an INVALID row or a
  /// policy-blocked row; WARN on a SUSPECT, UNPROVEN or UNBOUND row the policy
  /// lets through; otherwise OK.
  public static func decide(
    validateLedger: PrecommitLedgerInput,
    scan: PrecommitScanInput,
  ) -> PrecommitResult {
    var blockReasons = ledgerReasons(validateLedger)
    if !scan.registryValid || !scan.evidenceValid {
      blockReasons += ledgerIntegrityReasons(scan.status.integrityErrors)
    }
    if scan.exitCode == 2 {
      blockReasons.append(PrecommitBlockReason(
        source: .scan,
        code: "SCAN_USAGE_ERROR",
        rowIdentifier: nil,
        message: "scan failed with a usage/config/internal error (exit 2)",
      ))
    }

    var warnings: [PrecommitWarning] = []
    for row in scan.status.rows {
      if let reason = rowBlockReason(row) {
        blockReasons.append(reason)
      } else if [.suspect, .unproven, .unbound].contains(row.status) {
        warnings.append(warning(row))
      }
    }

    let decision: PrecommitDecision = !blockReasons.isEmpty
      ? .block
      : warnings.isEmpty ? .clear : .warn
    return PrecommitResult(
      decision: decision,
      exitCode: decision == .block ? 1 : 0,
      blockReasons: blockReasons,
      warnings: warnings,
      messages: blockReasons.map { reason in
        "BLOCK: \(reason.message)"
      } + warnings.map(\.message),
    )
  }

  /// Any validate-ledger failure blocks: one reason per error, or one generic
  /// reason when it reported none.
  private static func ledgerReasons(_ validateLedger: PrecommitLedgerInput)
    -> [PrecommitBlockReason]
  {
    guard !validateLedger.isOK else {
      return []
    }
    guard !validateLedger.errors.isEmpty else {
      return [PrecommitBlockReason(
        source: .validateLedger,
        code: "LEDGER_INVALID",
        rowIdentifier: nil,
        message: "validate-ledger reported the evidence ledger or binding registry as invalid",
      )]
    }
    return validateLedger.errors.map { error in
      PrecommitBlockReason(
        source: .validateLedger,
        code: error.code,
        rowIdentifier: nil,
        message: "validate-ledger (\(error.scope.rawValue)): \(error.message)",
      )
    }
  }

  /// An INVALID row blocks with its first reason; otherwise a policy-blocked
  /// row blocks as FRESHNESS_POLICY_BLOCK.
  private static func rowBlockReason(_ row: FreshnessRow) -> PrecommitBlockReason? {
    if row.status == .invalid {
      let code = firstReasonCode(row)
      return PrecommitBlockReason(
        source: .scan,
        code: code,
        rowIdentifier: row.rowIdentifier,
        message: "INVALID row \(row.rowIdentifier): \(code)",
      )
    }
    guard row.policyBlock else {
      return nil
    }
    return PrecommitBlockReason(
      source: .scan,
      code: "FRESHNESS_POLICY_BLOCK",
      rowIdentifier: row.rowIdentifier,
      message: "freshness policy blocks \(row.rowIdentifier) (status \(row.status.rawValue)); "
        + requiredAction(row),
    )
  }

  /// `formatPrecommitWarning`: the loud block spec 10.1 mandates.
  public static func warning(_ row: FreshnessRow) -> PrecommitWarning {
    let reason = firstReasonCode(row)
    let action = requiredAction(row)
    return PrecommitWarning(
      rowIdentifier: row.rowIdentifier,
      status: row.status,
      reason: reason,
      requiredAction: action,
      message: [
        "USE-CASE ROW \(row.status.rawValue)",
        "row: \(row.rowIdentifier)",
        "reason: \(reason)",
        "required action: \(action)",
      ].joined(separator: "\n"),
    )
  }

  /// `formatFreshnessPrSummary` (spec 10.2): the counts, each INVALID row, each
  /// SUSPECT / UNPROVEN / UNBOUND row with its required action, and every
  /// inferred Swift span.
  public static func pullRequestSummary(_ status: FreshnessStatus) -> String {
    let summary = status.summary
    var lines = [
      "USE-CASE FRESHNESS SUMMARY (policy: \(status.policyMode.rawValue))",
      "fresh: \(summary.fresh)  suspect: \(summary.suspect)  unproven: \(summary.unproven)  "
        + "unbound: \(summary.unbound)  invalid: \(summary.invalid)  "
        + "policy_blocked: \(summary.policyBlocked)",
    ]

    let invalidRows = status.rows.filter { row in
      row.status == .invalid
    }
    lines += ["", "INVALID rows:"]
    if invalidRows.isEmpty {
      lines.append("- (none)")
    }
    for row in invalidRows {
      lines.append("- \(row.rowIdentifier)  reason: \(firstReasonCode(row))")
      lines.append("  required action: \(requiredAction(row))")
    }

    let attentionRows = status.rows.filter { row in
      [.suspect, .unproven, .unbound].contains(row.status)
    }
    lines += ["", "SUSPECT / UNPROVEN / UNBOUND rows:"]
    if attentionRows.isEmpty {
      lines.append("- (none)")
    }
    for row in attentionRows {
      lines.append(
        "- \(row.rowIdentifier)  status: \(row.status.rawValue)  reason: \(firstReasonCode(row))",
      )
      lines.append("  required action: \(requiredAction(row))")
    }

    for row in status.rows {
      for binding in row.currentBindings where binding.extentKind == .swiftFunctionInferred {
        lines += [
          "",
          "INFERRED SWIFT SPAN",
          "row: \(row.rowIdentifier)",
          "binding: \(binding.bindingSlug)",
          "file: \(binding.filePath)",
          "span: lines \(binding.span.startLine)-\(binding.span.endLine)",
          "span_sha256: \(binding.span.sha256)",
        ]
      }
    }
    return lines.joined(separator: "\n")
  }

  /// Ledger-level integrity errors — those carrying no `row_id` member at all
  /// (an explicit null is a member) — or one generic reason when there are
  /// none.
  private static func ledgerIntegrityReasons(_ errors: [JSONObject]) -> [PrecommitBlockReason] {
    let ledgerLevel = errors.filter { error in
      error["row_id"] == nil
    }
    guard !ledgerLevel.isEmpty else {
      return [PrecommitBlockReason(
        source: .scan,
        code: "LEDGER_INVALID",
        rowIdentifier: nil,
        message: "scan reported the evidence ledger or binding registry as invalid",
      )]
    }
    return ledgerLevel.map { error in
      // Freshness writes every integrity code and message as a string; a null
      // or absent message falls back to the code (`??`), an empty one does not.
      let code = error["code"]?.stringValue ?? ""
      let message = error["message"]?.stringValue ?? code
      return PrecommitBlockReason(
        source: .scan,
        code: code,
        rowIdentifier: nil,
        message: "scan ledger/registry: \(message)",
      )
    }
  }

  /// `row.reasons[0]?.code ?? row.status`. Freshness writes every reason code
  /// as a string.
  private static func firstReasonCode(_ row: FreshnessRow) -> String {
    row.reasons.first?["code"]?.stringValue ?? row.status.rawValue
  }

  /// `defaultRequiredAction`: the row's own action when it is a non-empty
  /// string (truthiness), else `uc bind` for UNBOUND and `uc prove` otherwise.
  private static func requiredAction(_ row: FreshnessRow) -> String {
    if let action = row.requiredAction, !action.isEmpty {
      return action
    }
    return row.status == .unbound
      ? "uc bind --row \(row.rowIdentifier)"
      : "uc prove --row \(row.rowIdentifier)"
  }
}
