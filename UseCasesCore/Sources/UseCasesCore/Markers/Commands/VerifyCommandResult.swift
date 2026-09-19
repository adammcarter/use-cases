/// A row verdict in the unsigned results ledger.
public enum VerificationStatus: String, Equatable, Sendable {
  case pass
  case fail
  case blocked
}

/// What the tool SAW run, as opposed to what the row declared: a named test
/// runner is a suite; anything else could be a real drive of the product.
public enum VerificationRunClass: String, Equatable, Sendable {
  case suite
  case command
}

/// One line of the unsigned results ledger (`ucase-verification-result-v1`).
///
/// The `verifier_*`, exit code and output hashes describe the verifier that
/// decided the verdict. `runClass` and `evidenceKindOverclaimed` are set only
/// on a record of a verifier that ran; `variantKey` only on a variant's record.
public struct VerificationResultRecord: Equatable, Sendable {
  public static let schemaIdentifier = "ucase-verification-result-v1"

  public let rowIdentifier: String
  public let status: VerificationStatus
  public let evidenceKind: String?
  public let verifierIdentifier: String?
  public let verifierKind: String?
  public let exitCode: Int?
  public let rowHash: String
  public let bindingSetHash: String
  public let spanSHA256s: [String]
  public let verificationContextHash: String
  public let standardOutputSHA256: String?
  public let standardErrorSHA256: String?
  public let createdAt: String
  public let variantKey: String?
  public let runClass: VerificationRunClass?
  public let evidenceKindOverclaimed: Bool?
  /// The HMAC a run adds once every record exists; nil until then.
  public internal(set) var runAttestation: String?

  /// The TypeScript record in its key order: the shared base (the variant key
  /// last), the verdict fields — the run class and overclaim between the
  /// verifier kind and the exit code when a verifier ran — and the
  /// attestation, assigned after the literal, at the very end.
  public var jsonValue: JSONValue {
    .object(fields)
  }

  var fields: JSONObject {
    var object = JSONObject([
      ("schema", .string(Self.schemaIdentifier)),
      ("row_id", .string(rowIdentifier)),
      ("slug", .string(rowIdentifier)),
      ("row_hash", .string(rowHash)),
      ("binding_set_hash", .string(bindingSetHash)),
      ("span_sha256s", .array(spanSHA256s.map(JSONValue.string))),
      ("verification_context_hash", .string(verificationContextHash)),
      ("created_at", .string(createdAt)),
    ])
    object["variant_key"] = variantKey.map(JSONValue.string)
    object["status"] = .string(status.rawValue)
    object["evidence_kind"] = Self.nullable(evidenceKind)
    object["verifier_id"] = Self.nullable(verifierIdentifier)
    object["verifier_kind"] = Self.nullable(verifierKind)
    object["run_class"] = runClass.map { runClass in
      .string(runClass.rawValue)
    }
    object["evidence_kind_overclaimed"] = evidenceKindOverclaimed.map(JSONValue.bool)
    object["exit_code"] = exitCode.map { code in
      .number(Double(code))
    } ?? .null
    object["stdout_sha256"] = Self.nullable(standardOutputSHA256)
    object["stderr_sha256"] = Self.nullable(standardErrorSHA256)
    object["run_attestation"] = runAttestation.map(JSONValue.string)
    return object
  }

  private static func nullable(_ text: String?) -> JSONValue {
    text.map(JSONValue.string) ?? .null
  }
}

/// What a dry run would do for one row: a plan, never evidence.
public struct VerifyPlannedRow: Equatable, Sendable {
  public enum Disposition: String, Equatable, Sendable {
    case run
    /// No resolvable verifier, or a variant family that cannot tell its
    /// variants apart.
    case blocked
    /// Binding integrity errors.
    case invalid
  }

  public let rowIdentifier: String
  public let verifierIdentifier: String?
  public let command: [String]?
  public let disposition: Disposition

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("verifier_id", verifierIdentifier.map(JSONValue.string) ?? .null),
      ("command", command.map { parts in
        .array(parts.map(JSONValue.string))
      } ?? .null),
      ("disposition", .string(disposition.rawValue)),
    ]))
  }
}

public struct VerifyCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let results: [VerificationResultRecord]
  public let outPath: String?
  /// Rows declaring demonstration-grade evidence for a verifier the tool can
  /// prove is a unit suite. Present on a real run only.
  public let overclaimedRows: [String]?
  /// Present on a dry run only, with `dryRun` true.
  public let planned: [VerifyPlannedRow]?
  public let dryRun: Bool?
  public let errors: [MarkerCommandFailure]

  init(
    exitCode: Int,
    results: [VerificationResultRecord] = [],
    outPath: String? = nil,
    overclaimedRows: [String]? = nil,
    planned: [VerifyPlannedRow]? = nil,
    errors: [MarkerCommandFailure],
  ) {
    self.exitCode = exitCode
    isOK = exitCode == 0
    self.results = results
    self.outPath = outPath
    self.overclaimedRows = overclaimedRows
    self.planned = planned
    dryRun = planned == nil ? nil : true
    self.errors = errors
  }

  /// The TypeScript's `fail({...})` spread: the defaults' keys first, then
  /// the partial's new keys in its own order.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("command", .string("verify")),
      ("ok", .bool(isOK)),
      ("results", .array(results.map(\.jsonValue))),
      ("out_path", outPath.map(JSONValue.string) ?? .null),
      ("errors", .array(errors.map(\.jsonValue))),
      ("exit_code", .number(Double(exitCode))),
    ])
    object["overclaimed_rows"] = overclaimedRows.map { rows in
      .array(rows.map(JSONValue.string))
    }
    object["planned"] = planned.map { rows in
      .array(rows.map(\.jsonValue))
    }
    object["dry_run"] = dryRun.map(JSONValue.bool)
    return .object(object)
  }
}
