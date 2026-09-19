/// A row's signed-tier freshness status (spec section 7).
public enum RowStatus: String, Equatable, Sendable {
  case fresh = "FRESH"
  case suspect = "SUSPECT"
  case unproven = "UNPROVEN"
  case unbound = "UNBOUND"
  case invalid = "INVALID"
}

/// How the policy gate blocks (spec 10.2).
public enum PolicyMode: String, Equatable, Sendable {
  case feature
  case release
  case custom
}

/// The keyless local-verification tier, reported beside the signed status and
/// never in place of it.
public enum LocalStatus: String, Equatable, Sendable {
  case verifiedLocal = "VERIFIED_LOCAL"
  case staleLocal = "STALE_LOCAL"
  case unattestedLocal = "UNATTESTED_LOCAL"
  case unverifiedLocal = "UNVERIFIED_LOCAL"
}

/// What a custom policy predicate is asked about, once per row.
public struct PolicyDecisionContext: Equatable, Sendable {
  public let rowIdentifier: String
  public let status: RowStatus
  public let requiredForRelease: Bool
  public let isInvalid: Bool
}

/// The caller's `custom` policy: true blocks the row.
public typealias CustomPolicyPredicate = @Sendable (PolicyDecisionContext) -> Bool

/// One row's UNSIGNED verification result, distilled from the results ledger.
public struct LocalVerificationResult: Equatable, Sendable {
  public let rowIdentifier: String
  public let contextHash: String
  public let bindingSetHash: String
  public let passed: Bool
  /// Whether a valid run attestation proves a run wrote the record. Nil when
  /// the caller does not model attestation; `scan` always sets it.
  public let attested: Bool?

  public init(
    rowIdentifier: String,
    contextHash: String,
    bindingSetHash: String,
    passed: Bool,
    attested: Bool?,
  ) {
    self.rowIdentifier = rowIdentifier
    self.contextHash = contextHash
    self.bindingSetHash = bindingSetHash
    self.passed = passed
    self.attested = attested
  }
}

/// A run the tool itself drove against the product for a row.
public struct PerformedRun: Equatable, Sendable {
  public let rowIdentifier: String
  public let argv: [String]?

  public init(
    rowIdentifier: String,
    argv: [String]?,
  ) {
    self.rowIdentifier = rowIdentifier
    self.argv = argv
  }
}

/// A loaded use-case row. The whole object is the row hash's input; the two
/// policies feed the policy hashes.
public struct FreshnessInputRow: Equatable, Sendable {
  public let fields: JSONObject
  public let rowIdentifier: String

  /// Nil when the object is outside the domain the TypeScript is defined on:
  /// `row_id` must be a string, both policies must be PRESENT (the TypeScript's
  /// canonical JSON throws on an absent one; the loader writes `null`), and a
  /// `variants` array must hold objects with string `key`s, as the use-case
  /// schema requires.
  public init?(fields: JSONObject) {
    guard let rowIdentifier = fields["row_id"]?.stringValue,
          fields.contains("verification_policy"),
          fields.contains("approval_policy")
    else {
      return nil
    }
    if let variants = fields["variants"]?.arrayValue {
      guard variants.allSatisfy({ variant in
        variant["key"]?.stringValue != nil
      }) else {
        return nil
      }
    }
    self.fields = fields
    self.rowIdentifier = rowIdentifier
  }

  var verificationPolicy: JSONValue {
    fields["verification_policy"] ?? .null
  }

  var approvalPolicy: JSONValue {
    fields["approval_policy"] ?? .null
  }

  /// `approval_policy.required_for_release === true`.
  var requiredForRelease: Bool {
    approvalPolicy["required_for_release"] == .bool(true)
  }

  /// The declared variant keys in code-unit order (stable), or empty when
  /// `variants` is not an array.
  var familyVariantKeys: [String] {
    JavaScriptString.sorted((fields["variants"]?.arrayValue ?? []).compactMap { variant in
      variant["key"]?.stringValue
    })
  }
}

/// A trusted, already signature- and schema-validated passing proof event.
///
/// Carried as the JSON it is, so every leaf compares and prints exactly as the
/// TypeScript's does — including a leaf the schema would forbid.
public struct FreshnessProofEvent: Equatable, Sendable {
  public let value: JSONObject
  let rowIdentifier: String
  let createdAt: String
  let items: [JSONObject]

  /// Nil outside the domain the TypeScript is defined on: the `producer`,
  /// `row`, `verification` and `bindings` members must be objects (reading
  /// through a missing one throws a TypeError), and `row.row_id`, `created_at`
  /// and every item's `binding_slug` — which key maps and orderings — must be
  /// strings.
  public init?(json: JSONValue) {
    guard let value = json.objectValue,
          value["producer"]?.objectValue != nil,
          value["verification"]?.objectValue != nil,
          let rowIdentifier = value["row"]?["row_id"]?.stringValue,
          let createdAt = value["created_at"]?.stringValue,
          let itemValues = value["bindings"]?["items"]?.arrayValue
    else {
      return nil
    }
    let items = itemValues.compactMap(\.objectValue)
    guard items.count == itemValues.count,
          items.allSatisfy({ item in
            item["binding_slug"]?.stringValue != nil
          })
    else {
      return nil
    }
    self.value = value
    self.rowIdentifier = rowIdentifier
    self.createdAt = createdAt
    self.items = items
  }

  func row(_ key: String) -> JSONValue? {
    value["row"]?[key]
  }

  func verification(_ key: String) -> JSONValue? {
    value["verification"]?[key]
  }

  var bindingSetHash: JSONValue? {
    value["bindings"]?["binding_set_hash"]
  }

  /// `{ event_id, created_at, commit }`; a member the event lacks is absent.
  var reference: JSONValue {
    var object = JSONObject()
    object["event_id"] = value["event_id"]
    object["created_at"] = value["created_at"]
    object["commit"] = value["producer"]?["commit"]
    return .object(object)
  }
}

/// Everything `deriveFreshness` consumes. Pure: the timestamp is injected.
public struct FreshnessInput: Sendable {
  public var rows: [FreshnessInputRow]
  public var registry: MaterializedRegistry
  public var scan: ScanResult
  public var evidence: [FreshnessProofEvent]
  public var policyMode: PolicyMode
  /// Only consulted in `custom` mode.
  public var customPolicy: CustomPolicyPredicate?
  /// Only consulted in `release` mode.
  public var releaseGate: WorkspaceReleaseGate?
  /// Each row's freshly recomputed verification context hash, in the order a
  /// `Map` would be built from them (a later entry for a row wins). Nil when
  /// the caller does not bind proofs to their context.
  public var currentContextHashes: [(rowIdentifier: String, contextHash: String)]?
  /// Nil emits no `local_status` at all.
  public var localResults: [LocalVerificationResult]?
  /// Nil emits no `performed_run` at all.
  public var performedRuns: [PerformedRun]?
  public var generatedAt: String
  public var productRoot: String?
  public var tool: ProductVersion.VersionInfo?
  /// Ledger- or registry-level integrity errors not tied to one row, as the
  /// caller built them.
  public var globalIntegrityErrors: [JSONObject]?

  public init(
    rows: [FreshnessInputRow],
    registry: MaterializedRegistry,
    scan: ScanResult,
    evidence: [FreshnessProofEvent],
    policyMode: PolicyMode,
    generatedAt: String,
  ) {
    self.rows = rows
    self.registry = registry
    self.scan = scan
    self.evidence = evidence
    self.policyMode = policyMode
    self.generatedAt = generatedAt
  }
}
