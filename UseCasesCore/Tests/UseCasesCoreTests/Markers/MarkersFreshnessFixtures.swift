import Testing
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``MarkersFreshnessGoldenCorpus``:
/// the verifier presets and resolver, the verification context hash and the
/// freshness state machine.
///
/// Inputs are rebuilt from the corpus JSON through the real Swift pipeline — the
/// registry, the scanner, the proof-event and row domains — so each case runs
/// every layer the TypeScript ran, and the result is compared as wire bytes.
enum MarkersFreshnessFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MarkersFreshnessGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func root() throws -> JSONValue {
    try corpus.get()
  }

  static func section(_ name: String) throws -> [JSONValue] {
    try #require(root()[name]?.arrayValue, "corpus has no section \(name)")
  }

  static func entry(
    _ caseName: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let match = try section(sectionName).first { candidate in
      candidate["name"]?.stringValue == caseName
    }
    return try #require(match, "corpus section \(sectionName) has no case \(caseName)")
  }

  static func string(
    _ value: JSONValue,
    _ key: String,
  ) throws -> String {
    try MarkersFixtures.string(value, key)
  }

  static func wire(_ value: JSONValue) -> String {
    JSONWriter.encode(value)
  }

  /// The corpus's `{ default?, verifiers }` workspace shape; absent is empty.
  static func workspace(_ value: JSONValue?) -> ResolvedWorkspaceVerifiers {
    var verifiers: [String: WorkspaceVerifierEntry] = [:]
    for pair in value?["verifiers"]?.objectValue?.pairs ?? [] {
      if let entry = pair.value.objectValue {
        verifiers[pair.key] = WorkspaceVerifierEntry(value: entry)
      }
    }
    return ResolvedWorkspaceVerifiers(
      defaultVerifierIdentifier: value?["default"]?.stringValue,
      verifiers: verifiers,
    )
  }

  /// The corpus policy member: absent when the case says the TypeScript was
  /// given none.
  static func policy(_ entry: JSONValue) -> JSONValue? {
    entry["has_policy"] == .bool(true) ? entry["policy"] : nil
  }

  /// The predicates the generator names, with the same meaning.
  static let customPolicies: [String: CustomPolicyPredicate] = [
    "always_true": { _ in true },
    "always_false": { _ in false },
    "status_is_suspect": { context in
      context.status == .suspect
    },
    "required_for_release": { context in
      context.requiredForRelease
    },
    "is_invalid": { context in
      context.isInvalid
    },
    "row_is_alpha_b": { context in
      context.rowIdentifier == "alpha.b"
    },
  ]

  /// A freshness case's input, rebuilt the way the generator built it.
  static func freshnessInput(_ caseName: String) throws -> FreshnessInput {
    let entry = try entry(caseName, in: "freshness")
    var input = try FreshnessInput(
      rows: rows(entry),
      registry: registry(entry),
      scan: scan(entry),
      evidence: #require(entry["evidence"]?.arrayValue).map { event in
        try #require(FreshnessProofEvent(json: event))
      },
      policyMode: #require(PolicyMode(rawValue: string(entry, "policy_mode"))),
      generatedAt: string(entry, "generated_at"),
    )
    if let name = entry["custom_policy"]?.stringValue {
      input.customPolicy = try #require(customPolicies[name])
    }
    input.releaseGate = WorkspaceReleaseGate.normalize(entry["release_gate"])
    input.currentContextHashes = try entry["current_context_hashes"]?.arrayValue.map { pairs in
      try pairs.map { pair in
        let members = try #require(pair.arrayValue)
        return try (#require(members.first?.stringValue), #require(members.last?.stringValue))
      }
    }
    input.localResults = try entry["local_results"]?.arrayValue.map { results in
      try results.map(localResult)
    }
    input.performedRuns = try entry["performed_runs"]?.arrayValue.map { runs in
      try runs.map { run in
        try PerformedRun(
          rowIdentifier: string(run, "row_id"),
          argv: run["argv"]?.arrayValue?.compactMap(\.stringValue),
        )
      }
    }
    input.globalIntegrityErrors = try entry["global_integrity_errors"]?.arrayValue.map { errors in
      try errors.map { error in
        try #require(error.objectValue)
      }
    }
    if let tool = entry["tool"] {
      input.tool = try ProductVersion.VersionInfo(
        name: string(tool, "name"),
        version: string(tool, "version"),
      )
    }
    input.productRoot = entry["product_root"]?.stringValue
    return input
  }

  private static func rows(_ entry: JSONValue) throws -> [FreshnessInputRow] {
    try #require(entry["rows"]?.arrayValue).map { row in
      let fields = try #require(row.objectValue)
      return try #require(FreshnessInputRow(fields: fields))
    }
  }

  private static func registry(_ entry: JSONValue) throws -> MaterializedRegistry {
    var registry = MaterializedRegistry()
    for pair in try #require(entry["registry"]?.arrayValue) {
      let row = try #require(pair.arrayValue?.first?.stringValue)
      for slug in try #require(pair.arrayValue?.last?.arrayValue) {
        try registry.register(#require(slug.stringValue), to: row)
      }
    }
    return registry
  }

  private static func scan(_ entry: JSONValue) throws -> ScanResult {
    let inputs = try #require(entry["files"]?.arrayValue).map { file in
      try ScanInput(filePath: string(file, "file_path"), contents: string(file, "contents"))
    }
    let scanned = MarkerScanner.scanFiles(inputs)
    let extra = try #require(entry["extra_errors"]?.arrayValue).map { error in
      let code = try string(error, "code")
      let scanCode = try #require(
        MarkerErrorCode(rawValue: code).map(ScanErrorCode.marker)
          ?? SwiftFunctionErrorCode(rawValue: code).map(ScanErrorCode.swiftFunction),
      )
      return try MarkerError(
        code: scanCode,
        message: string(error, "message"),
        filePath: string(error, "file_path"),
        line: Int(#require(error["line"]?.numberValue)),
        slug: error["slug"]?.stringValue,
      )
    }
    return ScanResult(
      files: scanned.files,
      bindings: scanned.bindings,
      errors: scanned.errors + extra,
    )
  }

  private static func localResult(_ value: JSONValue) throws -> LocalVerificationResult {
    try LocalVerificationResult(
      rowIdentifier: string(value, "row_id"),
      contextHash: string(value, "context_hash"),
      bindingSetHash: string(value, "binding_set_hash"),
      passed: #require(value["passed"]?.boolValue),
      attested: value["attested"]?.boolValue,
    )
  }
}

/// A read-only filesystem holding exactly the corpus's files, by code unit.
struct CorpusTextFiles: TextFileReading {
  let files: [CodeUnitKey: String]

  init(_ value: JSONValue?) {
    var files: [CodeUnitKey: String] = [:]
    for pair in value?.objectValue?.pairs ?? [] {
      files[CodeUnitKey(pair.key)] = pair.value.stringValue
    }
    self.files = files
  }

  func readText(atPath path: String) -> String? {
    files[CodeUnitKey(path)]
  }
}

/// Every path answers with its own name, so a hash over it pins which paths
/// were read.
struct EchoTextFiles: TextFileReading {
  func readText(atPath path: String) -> String? {
    "read:\(path)"
  }
}
