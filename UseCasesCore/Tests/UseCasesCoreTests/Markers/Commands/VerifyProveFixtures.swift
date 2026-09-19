import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``VerifyProveGoldenCorpus`` and
/// the replay of its cases over real temporary workspaces.
///
/// Every expected value — a result object, the requests the verifier runner
/// received, every file left on disk — is what the TypeScript produced. The
/// temporary root is spelled `<ROOT>`.
enum VerifyProveFixtures {
  private typealias Commands = MarkerCommandsFixtures

  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(VerifyProveGoldenCorpus.json))
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

  static func wire(
    _ value: JSONValue?,
    root: String,
  ) -> String {
    Commands.wire(value).replacingOccurrences(of: root, with: "<ROOT>")
  }

  /// A case's entries built under a fresh root; its steps are the caller's.
  static func materialized(
    _ caseName: String,
    in section: String,
  ) throws -> MaterializedCase {
    let entry = try entry(caseName, in: section)
    let (directory, root) = try Commands.temporaryRoot()
    try Commands.materialize(#require(entry["entries"]?.arrayValue), under: root)
    return try MaterializedCase(
      directory: directory,
      root: root,
      steps: #require(entry["steps"]?.arrayValue),
    )
  }

  static func context(root: String) throws -> ResolvedWorkspaceContext {
    try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: root + "/workspace"),
      registry: Commands.registry.get(),
    )
  }

  static func publicKeyResolver() throws -> PublicKeyResolver {
    try MarkerCommandInputs.singleKeyResolver(publicKey: string("public_key_pem"))
  }

  /// The corpus key, or a resolver that knows no key.
  static func resolver(_ withKey: Bool) throws -> PublicKeyResolver {
    guard withKey else {
      return { _, _ in nil }
    }
    return try publicKeyResolver()
  }

  /// No default read may reach the real home directory: a step that wants
  /// the default location names it; every other one points at nothing.
  static func runKeyLocation(
    _ options: JSONValue,
    root: String,
  ) throws -> RunKeyLocation {
    let path = options["default_run_key"]?.boolValue == true
      ? try root + "/" + string("default_run_key_path")
      : root + "/no-run-key/run-key"
    return RunKeyLocation(environment: ["UC_RUN_KEY_FILE": path], homeDirectory: root + "/no-home")
  }

  static func verifyOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    root: String,
  ) throws -> VerifyCommandOptions {
    var verify = try VerifyCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      publicKeyResolver: resolver(options["public_key"]?.boolValue == true),
      generatedAt: string("generated_at"),
    )
    verify.trustedKeyConfigured = options["trusted_key_configured"]?.boolValue
    verify.all = options["all"]?.boolValue ?? false
    verify.rowIdentifier = options["row"]?.stringValue
    verify.outPath = options["out"]?.stringValue.map { path in
      path.isEmpty ? "" : root + "/" + path
    }
    verify.dryRun = options["dry_run"]?.boolValue ?? false
    verify.baseReference = options["base_ref"]?.stringValue
    verify.repositoryWorkingDirectory = context.workspaceRoot
    if options["default_run_key"]?.boolValue != true {
      verify
        .runKeyPath = try root + "/" +
        (options["run_key_path"]?.stringValue ?? string("run_key_path"))
    }
    return verify
  }

  static func proveOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
    root: String,
  ) throws -> ProveCommandOptions {
    let ticks = ProofTicks()
    var prove = try ProveCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      publicKeyResolver: resolver(options["public_key"]?.boolValue != false),
      generatedAt: string("generated_at"),
      identifierFactory: ticks.identifier,
    )
    prove.rowIdentifier = options["row"]?.stringValue
    prove.all = options["all"]?.boolValue ?? false
    prove.refresh = options["refresh"]?.boolValue ?? false
    prove.trustedContinuousIntegration = options["trusted_ci"]?.boolValue ?? false
    prove.append = options["append"]?.boolValue ?? false
    prove.dryRun = options["dry_run"]?.boolValue ?? false
    prove.verificationResults = try options["results_file"]?.stringValue.map { path in
      try results(atPath: root + "/" + path)
    }
    prove.unsafeAssumeVerificationPassed = options["unsafe_assume"]?.boolValue ?? false
    if options["signing_key"]?.boolValue == true {
      prove.signingKey = try ProveSigningKey(
        privateKeyPEM: string("private_key_pem"),
        keyIdentifier: string("key_id"),
      )
    }
    prove.producer = options["producer"].map { producer in
      ProveProducer(
        identifier: producer["id"]?.stringValue,
        version: producer["version"]?.stringValue,
        runIdentifier: producer["ci_run_id"]?.stringValue,
        repository: producer["repo"]?.stringValue,
        commit: producer["commit"]?.stringValue,
      )
    }
    if let environment = options["authority_environment"]?.objectValue {
      prove.authority = ProveCommand.authorityRecord(CiAuthority.detect(
        environment: Dictionary(uniqueKeysWithValues: environment.pairs.compactMap { pair in
          pair.value.stringValue.map { value in
            (pair.key, value)
          }
        }),
      ))
    } else if let options = options.objectValue, options.contains("authority_record") {
      prove.authority = options["authority_record"]
    }
    prove.baseReference = options["base_ref"]?.stringValue
    prove.repositoryWorkingDirectory = context.workspaceRoot
    return prove
  }

  static func proveEnvironment(_ options: JSONValue) -> [String: String] {
    guard let value = options["unsafe_environment"]?.stringValue else {
      return [:]
    }
    return [ProveCommand.allowUnsafeVerificationVariable: value]
  }

  /// The results file as the CLI reads it for prove: each non-blank trimmed
  /// line parsed.
  static func results(atPath path: String) throws -> [JSONValue] {
    try JavaScriptString.split(NodeFile.readText(atPath: path), on: CodeUnits.lineFeed)
      .map(JavaScriptString.trim)
      .filter { !$0.isEmpty }
      .map { line in
        try JSONParser.parse(line)
      }
  }

  /// The tree as the corpus records it, with what ed25519 randomness makes
  /// differ removed from every proof ledger: each signature's value, and every
  /// non-genesis `previous_entry_hash`, which hashes the entry before it,
  /// signature included. Both are checked for what they must be instead.
  static func maskedSnapshot(_ root: String) throws -> String {
    try maskedWire(Commands.snapshot(root), root: root)
  }

  static func maskedWire(
    _ snapshot: JSONValue?,
    root: String,
  ) -> String {
    let entries = (snapshot?.arrayValue ?? []).map { entry -> JSONValue in
      guard var parts = entry.arrayValue, parts.count == 4,
            parts[1].stringValue?.hasSuffix("proofs.jsonl") == true,
            let contents = parts[2].stringValue
      else {
        return entry
      }
      parts[2] = .string(maskProofLedger(contents))
      return .array(parts)
    }
    return wire(.array(entries), root: root)
  }

  static func maskProofLedger(_ text: String) -> String {
    text
      .replacingOccurrences(
        of: #"("signature":\{"alg":"ed25519","key_id":"[^"]*","value":")[A-Za-z0-9+/=]+""#,
        with: "$1<signature>\"",
        options: .regularExpression,
      )
      .replacingOccurrences(
        of: #"("previous_entry_hash":")sha256:(?!0{64}")[0-9a-f]{64}""#,
        with: "$1<chained>\"",
        options: .regularExpression,
      )
  }

  /// The proof ledger's parsed events, oldest first.
  static func proofEvents(_ root: String) throws -> [EvidenceLine] {
    let path = root + "/workspace/.use-cases/proofs.jsonl"
    guard FileManager.default.fileExists(atPath: path) else {
      return []
    }
    return try EvidenceLedger.read(NodeFile.readText(atPath: path)).lines
  }
}

/// A corpus case built on disk. Holding `directory` keeps the tree alive.
struct MaterializedCase {
  let directory: TemporaryDirectory
  let root: String
  let steps: [JSONValue]
}

/// The generator's prove id factory: `proof-0000`, `proof-0001`, … per step.
final class ProofTicks {
  private var tick = 0

  func identifier() -> String {
    defer {
      tick += 1
    }
    let digits = String(tick)
    return "proof-" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
  }
}

/// The generator's scripted verifier: an outcome per argv joined with a space,
/// else the default, else a clean pass. Every request is recorded.
final class ScriptedSpawnRunner: VerifySpawnRunning {
  private let outcomes: JSONObject
  private let fallback: JSONValue?
  private(set) var requests: [VerifySpawnRequest] = []

  init(_ script: JSONValue?) {
    outcomes = script?["outcomes"]?.objectValue ?? JSONObject()
    fallback = script?["default"]
  }

  func run(_ request: VerifySpawnRequest) throws(VerifySpawnError) -> VerifySpawnResult {
    requests.append(request)
    let outcome = outcomes[request.command.joined(separator: " ")] ?? fallback
    guard let outcome else {
      return VerifySpawnResult(
        exitCode: 0,
        timedOut: false,
        standardOutput: "ok\n",
        standardError: "",
      )
    }
    return VerifySpawnResult(
      exitCode: Int(outcome["exit_code"]?.numberValue ?? -1),
      timedOut: outcome["timed_out"]?.boolValue ?? false,
      standardOutput: outcome["stdout"]?.stringValue ?? "",
      standardError: outcome["stderr"]?.stringValue ?? "",
    )
  }
}
