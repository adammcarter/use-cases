import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``ScanImpactGoldenCorpus`` and
/// the replay of its cases over real temporary workspaces.
///
/// Every expected value is what the TypeScript produced. The temporary root is
/// spelled `<ROOT>` in the corpus; actual output is rewritten the same way
/// before it is compared as bytes.
enum ScanImpactFixtures {
  private typealias Commands = MarkerCommandsFixtures

  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(ScanImpactGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func root() throws -> JSONValue {
    try corpus.get()
  }

  static func entry(
    _ caseName: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let section = try #require(root()[sectionName]?.arrayValue, "corpus has no \(sectionName)")
    let match = section.first { candidate in
      candidate["name"]?.stringValue == caseName
    }
    return try #require(match, "\(sectionName) has no case \(caseName)")
  }

  static func string(_ key: String) throws -> String {
    try #require(root()[key]?.stringValue, "corpus has no \(key)")
  }

  /// `value` as the corpus spells it: bytes, with the root written `<ROOT>`,
  /// and V8's parser text cut from every JSON_PARSE_ERROR message.
  static func wire(
    _ value: JSONValue?,
    root: String,
  ) -> String {
    Commands.wire(value.map(withoutEngineText)).replacingOccurrences(of: root, with: "<ROOT>")
  }

  /// Byte equality. A mismatch records only where the bytes first part, so a
  /// failing case reads as one line rather than two whole result objects.
  static func expectSameBytes(
    _ actual: String,
    _ expected: String?,
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    let actualBytes = Array(actual.utf8)
    let expectedBytes = Array((expected ?? "<absent>").utf8)
    guard actualBytes != expectedBytes else {
      return
    }
    let offset = zip(actualBytes, expectedBytes).prefix { pair in
      pair.0 == pair.1
    }.count
    let excerpt = { (bytes: [UInt8]) in
      UTF8Text.decodeReplacingInvalid(Array(bytes[max(0, offset - 40) ..< min(
        bytes.count,
        offset + 60,
      )]))
    }
    let actualExcerpt = excerpt(actualBytes)
    let expectedExcerpt = excerpt(expectedBytes)
    Issue.record(
      "\(label) differs at byte \(offset): actual …\(actualExcerpt)… expected …\(expectedExcerpt)…",
      sourceLocation: sourceLocation,
    )
  }

  /// ``LedgerComparison``'s one allowance, applied to every string that
  /// carries a parse error — precommit copies the message into its own reason
  /// and message lines. Everything up to ` is not valid JSON: ` is compared.
  static func withoutEngineText(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(elements):
      return .array(elements.map(withoutEngineText))
    case let .object(object):
      var copy = JSONObject()
      for pair in object.pairs {
        copy[pair.key] = withoutEngineText(pair.value)
      }
      return .object(copy)
    case let .string(text):
      guard let range = text.range(of: LedgerComparison.parseErrorMarker) else {
        return value
      }
      return .string(String(text[..<range.upperBound]) + "<engine message>")
    default:
      return value
    }
  }

  /// A step's kind when it only changes the workspace, applied here.
  static func applyWorkspaceStep(
    _ step: JSONValue,
    root: String,
  ) throws -> Bool {
    let kind = try #require(step["kind"]?.stringValue)
    switch kind {
    case "write":
      let path = try #require(step["path"]?.stringValue)
      try Commands.materialize(
        [.array([
          .string("file"),
          .string(path),
          #require(step["contents"]),
          .number(step["mode"]?.numberValue ?? 0o644),
        ])],
        under: root,
      )
    case "remove":
      let path = try #require(step["path"]?.stringValue)
      try FileManager.default.removeItem(atPath: root + "/" + path)
    case "chmod":
      try Commands.materialize([chmodEntry(step)], under: root)
    case "git":
      let arguments = try #require(step["arguments"]?.arrayValue).compactMap(\.stringValue)
      _ = try GitProcessRunner().run(arguments, workingDirectory: root + "/workspace")
    default:
      return false
    }
    return true
  }

  /// The `chmod` steps of a case as fixture entries, so they can be undone.
  static func chmodEntries(_ steps: [JSONValue]) -> [JSONValue] {
    steps.filter { step in
      step["kind"]?.stringValue == "chmod"
    }.map(chmodEntry)
  }

  private static func chmodEntry(_ step: JSONValue) -> JSONValue {
    .array([.string("chmod"), step["path"] ?? .null, step["mode"] ?? .null])
  }

  /// The workspace context a step names (`workspace/` by default).
  static func context(
    _ options: JSONValue,
    root: String,
  ) throws -> ResolvedWorkspaceContext {
    let workspace = options["workspace"]?.stringValue ?? "workspace"
    return try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: root + "/" + workspace),
      registry: MarkerCommandsFixtures.registry.get(),
    )
  }

  /// A run-key location with nothing in it: a replayed step names its key
  /// explicitly, so a default read must find nothing, never the real home.
  static func emptyRunKeyLocation(_ root: String) -> RunKeyLocation {
    RunKeyLocation(
      environment: ["UC_RUN_KEY_FILE": root + "/no-run-key/run-key"],
      homeDirectory: root + "/no-home",
    )
  }

  static func scanOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    root: String,
  ) throws -> ScanCommandOptions {
    let publicKey = try string("public_key_pem")
    var resolver: PublicKeyResolver = { _, _ in
      nil
    }
    if options["public_key"]?.boolValue == true {
      resolver = MarkerCommandInputs.singleKeyResolver(publicKey: publicKey)
    }
    let evidencePath: String = if let path = options["evidence_path"]?.stringValue {
      root + "/" + path
    } else {
      NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl")
    }
    let policyMode =
      try #require(PolicyMode(rawValue: options["policy_mode"]?.stringValue ?? "feature"))
    let generatedAt = try string("generated_at")
    var scan = ScanCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: evidencePath,
      policyMode: policyMode,
      publicKeyResolver: resolver,
      generatedAt: generatedAt,
    )
    scan.trustedKeyConfigured = options["trusted_key_configured"]?.boolValue
    scan.baseReference = options["base_ref"]?.stringValue
    scan.repositoryWorkingDirectory = context.workspaceRoot
    scan.resultsPath = options["results_path"]?.stringValue.map { path in
      root + "/" + path
    }
    let runKeyPath = try options["run_key_path"]?.stringValue ?? string("run_key_path")
    scan.runKeyPath = root + "/" + runKeyPath
    scan.performedRuns = options["performed_runs"]?.arrayValue.map { rows in
      rows.compactMap(\.stringValue).map { row in
        PerformedRun(rowIdentifier: row, argv: ["injected"])
      }
    }
    scan.gate = options["gate"]?.boolValue ?? false
    return scan
  }

  static func impactOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
  ) throws -> ImpactCommandOptions {
    let generatedAt = try string("generated_at")
    var impact = ImpactCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      publicKeyResolver: { _, _ in nil },
      generatedAt: generatedAt,
    )
    impact.repositoryWorkingDirectory = context.workspaceRoot
    impact.base = options["base"]?.stringValue
    impact.staged = options["staged"]?.boolValue ?? false
    return impact
  }

  static func thrown(_ error: MarkerCommandError) -> JSONValue {
    .object(JSONObject([("message", .string(error.message))]))
  }
}

/// Precommit inputs rebuilt from the TypeScript slices the corpus records.
///
/// A status member the result object does not carry (a binding's markers and
/// bytes, a proof event's body) is filled with a placeholder precommit never
/// reads; ``status(_:)`` is checked to write back exactly what it read.
enum PrecommitInputDecoding {
  static func ledger(_ value: JSONValue) throws -> PrecommitLedgerInput {
    let errors = try #require(value["errors"]?.arrayValue).map { error in
      try LedgerErrorReport(
        scope: #require(LedgerErrorScope(rawValue: error["scope"]?.stringValue ?? "")),
        code: #require(error["code"]?.stringValue),
        line: error["line"]?.numberValue.map { line in
          Int(line)
        },
        message: #require(error["message"]?.stringValue),
      )
    }
    return try PrecommitLedgerInput(
      isOK: #require(value["ok"]?.boolValue as Bool?),
      exitCode: integer(value, "exit_code"),
      evidenceValid: #require(value["evidence_valid"]?.boolValue as Bool?),
      registryValid: #require(value["registry_valid"]?.boolValue as Bool?),
      appendOnly: #require(value["append_only"]?.boolValue as Bool?),
      errors: errors,
    )
  }

  static func scan(_ value: JSONValue) throws -> PrecommitScanInput {
    try PrecommitScanInput(
      exitCode: integer(value, "exit_code"),
      registryValid: #require(value["registry_valid"]?.boolValue as Bool?),
      evidenceValid: #require(value["evidence_valid"]?.boolValue as Bool?),
      status: status(#require(value["status"])),
    )
  }

  static func status(_ value: JSONValue) throws -> FreshnessStatus {
    let tool = try #require(value["tool"])
    let claim = try #require(value["acceptance_claim"])
    let byEvidence = try #require(claim["by_evidence"])
    let summary = try #require(value["summary"])
    return try FreshnessStatus(
      generatedAt: #require(value["generated_at"]?.stringValue),
      tool: ProductVersion.VersionInfo(
        name: #require(tool["name"]?.stringValue),
        version: #require(tool["version"]?.stringValue),
      ),
      productRoot: #require(value["product_root"]?.stringValue),
      policyMode: #require(PolicyMode(rawValue: value["policy_mode"]?.stringValue ?? "")),
      guardOk: #require(value["guard_ok"]?.boolValue as Bool?),
      acceptanceClaim: AcceptanceClaim(
        proven: integer(claim, "proven"),
        total: integer(claim, "total"),
        claimable: #require(claim["claimable"]?.boolValue as Bool?),
        statement: #require(claim["statement"]?.stringValue),
        basis: #require(claim["basis"]?.stringValue),
        byEvidence: EvidenceTally(
          signedProof: integer(byEvidence, "signed_proof"),
          localRun: integer(byEvidence, "local_run"),
          performedRun: integer(byEvidence, "performed_run"),
        ),
        unattested: integer(claim, "unattested"),
      ),
      summary: FreshnessSummary(
        fresh: integer(summary, "fresh"),
        suspect: integer(summary, "suspect"),
        unproven: integer(summary, "unproven"),
        unbound: integer(summary, "unbound"),
        invalid: integer(summary, "invalid"),
        policyBlocked: integer(summary, "policy_blocked"),
        verifiedLocal: integer(summary, "verified_local"),
        staleLocal: integer(summary, "stale_local"),
        unverifiedLocal: integer(summary, "unverified_local"),
        unattestedLocal: integer(summary, "unattested_local"),
        performedRun: integer(summary, "performed_run"),
      ),
      integrityErrors: #require(value["integrity_errors"]?.arrayValue).map { error in
        try #require(error.objectValue)
      },
      rows: #require(value["rows"]?.arrayValue).map(row),
    )
  }

  private static func row(_ value: JSONValue) throws -> FreshnessRow {
    let rowIdentifier = try #require(value["row_id"]?.stringValue)
    let hashes = try value["row_hash"].map { rowHash in
      try FreshnessRowHashes(
        rowHash: #require(rowHash.stringValue),
        verificationPolicyHash: #require(value["verification_policy_hash"]?.stringValue),
        approvalPolicyHash: #require(value["approval_policy_hash"]?.stringValue),
      )
    }
    let localTier = value["local_status"].map { status in
      FreshnessLocalTier(
        status: status.stringValue.flatMap(LocalStatus.init(rawValue:)),
        reason: value["local_reason"]?.stringValue,
      )
    }
    let variants = try value["variant_local_status"]?.arrayValue.map { entries in
      try entries.map { entry in
        try VariantLocalStatus(
          key: #require(entry["key"]?.stringValue),
          status: #require(LocalStatus(rawValue: entry["local_status"]?.stringValue ?? "")),
        )
      }
    }
    return try FreshnessRow(
      rowIdentifier: rowIdentifier,
      hashes: hashes,
      status: #require(RowStatus(rawValue: value["status"]?.stringValue ?? "")),
      policyBlock: #require(value["policy_block"]?.boolValue as Bool?),
      reasons: #require(value["reasons"]?.arrayValue).map { reason in
        try #require(reason.objectValue)
      },
      knownBindingSlugs: strings(value, "known_binding_slugs"),
      currentBindingSlugs: strings(value, "current_binding_slugs"),
      missingRegisteredBindingSlugs: strings(value, "missing_registered_binding_slugs"),
      unregisteredCurrentBindingSlugs: strings(value, "unregistered_current_binding_slugs"),
      currentBindings: #require(value["current_bindings"]?.arrayValue).map { binding in
        try self.binding(binding, rowIdentifier: rowIdentifier)
      },
      matchingProofEvent: proofEvent(value["matching_proof_event"]),
      latestTrustedProofEvent: proofEvent(value["latest_trusted_proof_event"]),
      requiredAction: value["required_action"]?.stringValue,
      requiredForRelease: #require(value["required_for_release"]?.boolValue as Bool?),
      localTier: localTier,
      performedRun: value["performed_run"]?.boolValue,
      variantLocalStatus: variants,
      currentBindingSetHash: value["current_binding_set_hash"]?.stringValue,
    )
  }

  private static func binding(
    _ value: JSONValue,
    rowIdentifier: String,
  ) throws -> CurrentBindingRecord {
    try CurrentBindingRecord(
      bindingSlug: #require(value["binding_slug"]?.stringValue),
      rowIdentifier: rowIdentifier,
      suffix: nil,
      filePath: #require(value["file_path"]?.stringValue),
      commentPrefix: "//",
      extentKind: #require(BindingExtentKind(rawValue: value["extent_kind"]?.stringValue ?? "")),
      recognizerIdentifier: #require(value["recognizer_id"]?.stringValue),
      spanCanonicalizerIdentifier: #require(value["span_canon_id"]?.stringValue),
      startMarker: MarkerPosition(line: 0, column: 0),
      endMarker: nil,
      span: BindingSpan(
        startLine: integer(value, "span_start_line"),
        endLine: integer(value, "span_end_line"),
        startByte: 0,
        endByte: 0,
        sha256: #require(value["span_sha256"]?.stringValue),
      ),
      diagnostic: .explicit,
    )
  }

  /// A proof event carrying just the members its reference prints.
  private static func proofEvent(_ reference: JSONValue?) -> FreshnessProofEvent? {
    guard let reference = reference?.objectValue else {
      return nil
    }
    var producer = JSONObject()
    producer["commit"] = reference["commit"]
    var event = JSONObject()
    event["event_id"] = reference["event_id"]
    event["created_at"] = reference["created_at"]
    event["producer"] = .object(producer)
    event["row"] = .object(JSONObject([("row_id", .string(""))]))
    event["verification"] = .object(JSONObject())
    event["bindings"] = .object(JSONObject([("items", .array([]))]))
    // A nil here drops the reference, which the round-trip check reports.
    return FreshnessProofEvent(json: .object(event))
  }

  private static func strings(
    _ value: JSONValue,
    _ key: String,
  ) throws -> [String] {
    try #require(value[key]?.arrayValue).map { item in
      try #require(item.stringValue)
    }
  }

  private static func integer(
    _ value: JSONValue,
    _ key: String,
  ) throws -> Int {
    try Int(#require(value[key]?.numberValue, "missing \(key)"))
  }
}
