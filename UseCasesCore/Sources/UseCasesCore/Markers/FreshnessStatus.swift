/// The three hashes a row known to the matrix carries.
public struct FreshnessRowHashes: Equatable, Sendable {
  public let rowHash: String
  public let verificationPolicyHash: String
  public let approvalPolicyHash: String
}

/// The keyless local tier as emitted: both members present, either may be
/// null.
public struct FreshnessLocalTier: Equatable, Sendable {
  public let status: LocalStatus?
  public let reason: String?
}

/// One variant's local status inside a family's breakdown.
public struct VariantLocalStatus: Equatable, Sendable {
  public let key: String
  public let status: LocalStatus
}

/// One row of the freshness object (spec section 6).
public struct FreshnessRow: Equatable, Sendable {
  public let rowIdentifier: String
  /// Nil when the row is not in the matrix: the three members are then absent.
  public let hashes: FreshnessRowHashes?
  public let status: RowStatus
  public let policyBlock: Bool
  /// Each reason exactly as the TypeScript's literal spells it.
  public let reasons: [JSONObject]
  public let knownBindingSlugs: [String]
  public let currentBindingSlugs: [String]
  public let missingRegisteredBindingSlugs: [String]
  public let unregisteredCurrentBindingSlugs: [String]
  public let currentBindings: [CurrentBindingRecord]
  public let matchingProofEvent: FreshnessProofEvent?
  public let latestTrustedProofEvent: FreshnessProofEvent?
  public let requiredAction: String?
  public let requiredForRelease: Bool
  /// Nil when the caller supplied no local results.
  public let localTier: FreshnessLocalTier?
  /// Nil when the caller supplied no performed runs.
  public let performedRun: Bool?
  public let variantLocalStatus: [VariantLocalStatus]?
  /// Nil when the row has no registered current binding.
  public let currentBindingSetHash: String?

  /// Members in the order the TypeScript ASSIGNS them, which is not the order
  /// its interface declares them: the binding-set hash is written last.
  var jsonValue: JSONValue {
    var object = JSONObject([("row_id", .string(rowIdentifier))])
    if let hashes {
      object["row_hash"] = .string(hashes.rowHash)
      object["verification_policy_hash"] = .string(hashes.verificationPolicyHash)
      object["approval_policy_hash"] = .string(hashes.approvalPolicyHash)
    }
    object["status"] = .string(status.rawValue)
    object["policy_block"] = .bool(policyBlock)
    object["reasons"] = .array(reasons.map(JSONValue.object))
    object["known_binding_slugs"] = .array(knownBindingSlugs.map(JSONValue.string))
    object["current_binding_slugs"] = .array(currentBindingSlugs.map(JSONValue.string))
    object["missing_registered_binding_slugs"] =
      .array(missingRegisteredBindingSlugs.map(JSONValue.string))
    object["unregistered_current_binding_slugs"] =
      .array(unregisteredCurrentBindingSlugs.map(JSONValue.string))
    object["current_bindings"] = .array(currentBindings.map(Self.bindingOutput))
    object["matching_proof_event"] = matchingProofEvent?.reference ?? .null
    object["latest_trusted_proof_event"] = latestTrustedProofEvent?.reference ?? .null
    object["required_action"] = requiredAction.map(JSONValue.string) ?? .null
    object["required_for_release"] = .bool(requiredForRelease)
    if let localTier {
      object["local_status"] = localTier.status.map { status in
        .string(status.rawValue)
      } ?? .null
      object["local_reason"] = localTier.reason.map(JSONValue.string) ?? .null
    }
    object["performed_run"] = performedRun.map(JSONValue.bool)
    object["variant_local_status"] = variantLocalStatus.map { breakdown in
      .array(breakdown.map { entry in
        .object(JSONObject([
          ("key", .string(entry.key)),
          ("local_status", .string(entry.status.rawValue)),
        ]))
      })
    }
    object["current_binding_set_hash"] = currentBindingSetHash.map(JSONValue.string)
    return .object(object)
  }

  private static func bindingOutput(_ binding: CurrentBindingRecord) -> JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(binding.bindingSlug)),
      ("file_path", .string(binding.filePath)),
      ("extent_kind", .string(binding.extentKind.rawValue)),
      ("recognizer_id", .string(binding.recognizerIdentifier)),
      ("span_canon_id", .string(binding.spanCanonicalizerIdentifier)),
      ("span_sha256", .string(binding.span.sha256)),
      ("span_start_line", .number(Double(binding.span.startLine))),
      ("span_end_line", .number(Double(binding.span.endLine))),
    ]))
  }
}

/// The per-status and per-tier counts.
public struct FreshnessSummary: Equatable, Sendable {
  public internal(set) var fresh = 0
  public internal(set) var suspect = 0
  public internal(set) var unproven = 0
  public internal(set) var unbound = 0
  public internal(set) var invalid = 0
  public internal(set) var policyBlocked = 0
  public internal(set) var verifiedLocal = 0
  public internal(set) var staleLocal = 0
  public internal(set) var unverifiedLocal = 0
  public internal(set) var unattestedLocal = 0
  public internal(set) var performedRun = 0

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("fresh", .number(Double(fresh))),
      ("suspect", .number(Double(suspect))),
      ("unproven", .number(Double(unproven))),
      ("unbound", .number(Double(unbound))),
      ("invalid", .number(Double(invalid))),
      ("policy_blocked", .number(Double(policyBlocked))),
      ("verified_local", .number(Double(verifiedLocal))),
      ("stale_local", .number(Double(staleLocal))),
      ("unverified_local", .number(Double(unverifiedLocal))),
      ("unattested_local", .number(Double(unattestedLocal))),
      ("performed_run", .number(Double(performedRun))),
    ]))
  }
}

/// Where the proven count comes from, each row at its strongest tier.
public struct EvidenceTally: Equatable, Sendable {
  public internal(set) var signedProof = 0
  public internal(set) var localRun = 0
  public internal(set) var performedRun = 0
}

/// The acceptance conclusion, stated outright.
public struct AcceptanceClaim: Equatable, Sendable {
  public let proven: Int
  public let total: Int
  public let claimable: Bool
  public let statement: String
  public let basis: String
  public let byEvidence: EvidenceTally
  public let unattested: Int

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("proven", .number(Double(proven))),
      ("total", .number(Double(total))),
      ("claimable", .bool(claimable)),
      ("statement", .string(statement)),
      ("basis", .string(basis)),
      ("by_evidence", .object(JSONObject([
        ("signed_proof", .number(Double(byEvidence.signedProof))),
        ("local_run", .number(Double(byEvidence.localRun))),
        ("performed_run", .number(Double(byEvidence.performedRun))),
      ]))),
      ("unattested", .number(Double(unattested))),
    ]))
  }
}

/// The freshness object: the `use-cases scan` contract (ADR 0007 decision 8).
public struct FreshnessStatus: Equatable, Sendable {
  public let generatedAt: String
  public let tool: ProductVersion.VersionInfo
  public let productRoot: String
  public let policyMode: PolicyMode
  public let guardOk: Bool
  public let acceptanceClaim: AcceptanceClaim
  public let summary: FreshnessSummary
  /// Each error with the members its producer gave it, in that order.
  public let integrityErrors: [JSONObject]
  public let rows: [FreshnessRow]

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema", .string(MarkerConstants.statusSchemaIdentifier)),
      ("generated_at", .string(generatedAt)),
      ("tool", .object(JSONObject([
        ("name", .string(tool.name)),
        ("version", .string(tool.version)),
      ]))),
      ("product_root", .string(productRoot)),
      ("policy_mode", .string(policyMode.rawValue)),
      ("guard_ok", .bool(guardOk)),
      ("acceptance_claim", acceptanceClaim.jsonValue),
      ("summary", summary.jsonValue),
      ("integrity_errors", .array(integrityErrors.map(JSONValue.object))),
      ("rows", .array(rows.map(\.jsonValue))),
    ]))
  }
}
