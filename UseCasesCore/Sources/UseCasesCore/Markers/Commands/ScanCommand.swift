import Foundation

public struct ScanCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var evidencePath: String
  public var policyMode: PolicyMode
  public var publicKeyResolver: PublicKeyResolver
  /// Whether the caller configured trusted key material. Nil reads as true:
  /// an unresolved key id then fails closed. False is the keyless path, where
  /// a signed proof nobody can check is not corruption.
  public var trustedKeyConfigured: Bool?
  public var generatedAt: String
  public var commentConfiguration: CommentPrefixConfiguration?
  /// When set, the evidence ledger is also read at this ref for the
  /// append-only check.
  public var baseReference: String?
  /// Where `git show` runs, and the root the verification context hashes are
  /// taken from (the product root when nil).
  public var repositoryWorkingDirectory: String?
  /// The unsigned results ledger; nil reads
  /// `<data_root>/.use-cases/verification-results.jsonl`.
  public var resultsPath: String?
  /// The machine-local run key; nil reads the default location, resolved from
  /// the environment and home directory `run` is given.
  public var runKeyPath: String?
  /// Performed runs to use instead of replaying the observation ledger.
  public var performedRuns: [PerformedRun]?
  /// `scan --gate`: raise an otherwise passing exit code to 1 when a required
  /// row is below the mode's bar.
  public var gate: Bool

  public init(
    context: ResolvedWorkspaceContext,
    productRoot: String,
    bindingsPath: String,
    evidencePath: String,
    policyMode: PolicyMode,
    publicKeyResolver: @escaping PublicKeyResolver,
    generatedAt: String,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.evidencePath = evidencePath
    self.policyMode = policyMode
    self.publicKeyResolver = publicKeyResolver
    trustedKeyConfigured = nil
    self.generatedAt = generatedAt
    commentConfiguration = nil
    baseReference = nil
    repositoryWorkingDirectory = nil
    resultsPath = nil
    runKeyPath = nil
    performedRuns = nil
    gate = false
  }
}

/// Where the run key is looked for when the caller names no path: the
/// process environment and home directory, injected so a test never reads the
/// real one.
public struct RunKeyLocation: Sendable {
  public let environment: [String: String]
  public let homeDirectory: String

  public init(
    environment: [String: String],
    homeDirectory: String,
  ) {
    self.environment = environment
    self.homeDirectory = homeDirectory
  }

  /// This process's environment and home directory, `$HOME` first as node's
  /// `os.homedir()` reads it.
  public static var process: RunKeyLocation {
    let environment = ProcessInfo.processInfo.environment
    return RunKeyLocation(
      environment: environment,
      homeDirectory: environment["HOME"] ?? NSHomeDirectory(),
    )
  }

  var defaultPath: String {
    RunAttestation.defaultRunKeyPath(environment: environment, homeDirectory: homeDirectory)
  }
}

/// `ScanPreparation`: the shared pipeline `scan`, `impact` and `prove` read.
public struct ScanPreparation: Sendable {
  public let loaded: LoadedMarkerRows
  public let registry: MaterializedRegistry
  public let registryErrors: [RegistryError]
  /// The trusted, validated proof events.
  public let evidence: [JSONValue]
  public let evidenceErrors: [EvidenceError]
  /// The evidence errors that are real ledger corruption: all of them when a
  /// trusted key was configured, otherwise all but pure missing-key failures.
  public let evidenceIntegrityErrors: [EvidenceError]
  public let scan: ScanResult
  public let status: FreshnessStatus
}

public struct ScanCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let status: FreshnessStatus
  public let registryValid: Bool
  public let evidenceValid: Bool
  public let inferredSpans: [String]
  public let registryErrors: [RegistryError]
  public let evidenceErrors: [EvidenceError]
  /// Present only when the gate was requested.
  public let gate: ScanGateResult?

  /// The TypeScript result object, in its key order; `gate` absent, not null,
  /// when it was not requested.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("exit_code", .number(Double(exitCode))),
      ("ok", .bool(isOK)),
      ("status", status.jsonValue),
      ("registry_valid", .bool(registryValid)),
      ("evidence_valid", .bool(evidenceValid)),
      ("inferred_spans", .array(inferredSpans.map(JSONValue.string))),
      ("registry_errors", .array(registryErrors.map(\.jsonValue))),
      ("evidence_errors", .array(evidenceErrors.map(\.jsonValue))),
    ])
    object["gate"] = gate?.jsonValue
    return .object(object)
  }
}

/// `runScanCommand` (spec 8.2): rows, the registry, the evidence ledger, the
/// product's markers and the keyless tier in; the freshness status and an exit
/// code out. Strictly read-only.
public enum ScanCommand {
  public static func run(
    _ options: ScanCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
    runKeyLocation: RunKeyLocation = .process,
  ) throws(MarkerCommandError) -> ScanCommandResult {
    let prepared = try prepare(
      options,
      files: files,
      registry: registry,
      gitRunner: gitRunner,
      runKeyLocation: runKeyLocation,
    )
    let registryValid = prepared.registryErrors.isEmpty
    let evidenceValid = prepared.evidenceIntegrityErrors.isEmpty
    let inferredSpans = prepared.scan.bindings
      .compactMap(MarkerScanner.formatInferredSwiftSpanReport)

    var exitCode = ScanGate.exitCode(
      prepared.status,
      registryValid: registryValid,
      evidenceValid: evidenceValid,
    )
    // The gate only ever raises a passing scan; it never lowers 4, 3 or 1.
    var gate: ScanGateResult?
    if options.gate {
      let evaluated = ScanGate.evaluate(prepared.status, policyMode: options.policyMode)
      if evaluated.blocked, exitCode == 0 {
        exitCode = 1
      }
      gate = evaluated
    }

    return ScanCommandResult(
      exitCode: exitCode,
      isOK: exitCode == 0,
      status: prepared.status,
      registryValid: registryValid,
      evidenceValid: evidenceValid,
      inferredSpans: inferredSpans,
      registryErrors: prepared.registryErrors,
      evidenceErrors: prepared.evidenceErrors,
      gate: gate,
    )
  }

  /// `prepareScan`, in the TypeScript's order, so the first failure raised is
  /// the one it raises.
  public static func prepare(
    _ options: ScanCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
    runKeyLocation: RunKeyLocation = .process,
  ) throws(MarkerCommandError) -> ScanPreparation {
    let loaded = try loadRows(options.context, registry: registry)

    let bindingsText = try readText(options.bindingsPath, files: files) ?? ""
    let registryResult = BindingRegistry.validate(
      text: bindingsText,
      yamlRowIdentifiers: loaded.rowIdentifiers,
    )

    let evidence = try validateEvidence(
      options,
      loaded: loaded,
      files: files,
      gitRunner: gitRunner,
    )

    let scan = try scanSources(options, files: files)

    // Without a configured key, a signed proof nobody could check is the
    // ordinary keyless path, not corruption.
    let evidenceIntegrityErrors = options.trustedKeyConfigured ?? true
      ? evidence.errors
      : evidence.errors.filter { error in
        !EvidenceLedger.isKeyResolutionOnly(error)
      }

    var input = FreshnessInput(
      rows: loaded.rows,
      registry: registryResult.registry,
      scan: scan,
      evidence: evidence.events.compactMap(FreshnessProofEvent.init(json:)),
      policyMode: options.policyMode,
      generatedAt: options.generatedAt,
    )
    input.productRoot = options.productRoot
    input.currentContextHashes = try currentContextHashes(options, loaded: loaded, files: files)
    input.localResults = try localResults(options, files: files, runKeyLocation: runKeyLocation)
    input.performedRuns = options.performedRuns ?? LocalVerificationResults.performedRuns(
      context: options.context,
      loaded: loaded,
    )
    input.globalIntegrityErrors = globalIntegrityErrors(
      registryResult.errors,
      evidenceIntegrityErrors,
    )
    input.releaseGate = options.context.releaseGate
    let status = try derive(input)

    return ScanPreparation(
      loaded: loaded,
      registry: registryResult.registry,
      registryErrors: registryResult.errors,
      evidence: evidence.events,
      evidenceErrors: evidence.errors,
      evidenceIntegrityErrors: evidenceIntegrityErrors,
      scan: scan,
      status: status,
    )
  }

  /// The ledger read and, with a base ref, its base version. The base read is
  /// handed `evidencePath` exactly as given — at the CLI an ABSOLUTE path, which
  /// `git show` never finds, so the base reads as empty and the append-only
  /// comparison passes. Kept as the TypeScript has it.
  private static func validateEvidence(
    _ options: ScanCommandOptions,
    loaded: LoadedMarkerRows,
    files: some MarkerFileSystem,
    gitRunner: some GitRunning,
  ) throws(MarkerCommandError) -> EvidenceLedgerValidation {
    let evidenceText = try readText(options.evidencePath, files: files) ?? ""
    var baseText: String?
    if let baseReference = options.baseReference {
      do throws(GitError) {
        baseText = try AppendOnly.readBaseReferenceFile(
          baseReference: baseReference,
          path: options.evidencePath,
          workingDirectory: options.repositoryWorkingDirectory,
          runner: gitRunner,
        )
      } catch {
        throw .git(error)
      }
    }
    do throws(EvidenceLedgerError) {
      return try EvidenceLedger.validate(
        text: evidenceText,
        publicKeyResolver: options.publicKeyResolver,
        baseReferenceOldText: baseText,
        yamlRowIdentifiers: loaded.rowIdentifiers,
      )
    } catch {
      throw .evidenceLedger(error)
    }
  }

  private static func loadRows(
    _ context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(MarkerCommandError) -> LoadedMarkerRows {
    do throws(UseCaseMatrixError) {
      return try MarkerCommandInputs.loadMarkerRows(context: context, registry: registry)
    } catch {
      throw .useCaseMatrix(error)
    }
  }

  /// The product's source files, the data root skipped, scanned for markers.
  private static func scanSources(
    _ options: ScanCommandOptions,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> ScanResult {
    do throws(FileAccessError) {
      let inputs = try MarkerCommandInputs.collectSourceInputs(
        productRoot: options.productRoot,
        files: files,
        configuration: options.commentConfiguration,
        skipPaths: [options.context.dataRoot],
      )
      return MarkerScanner.scanFiles(inputs, configuration: options.commentConfiguration)
    } catch {
      throw .fileAccess(error)
    }
  }

  private static func derive(_ input: FreshnessInput) throws(MarkerCommandError)
    -> FreshnessStatus
  {
    do throws(CodeUnitCanonicalJSONError) {
      return try Freshness.derive(input)
    } catch {
      throw .canonicalJSON(error)
    }
  }

  /// Registry and ledger corruption as global integrity errors, each member
  /// the TypeScript leaves `undefined` absent rather than null.
  private static func globalIntegrityErrors(
    _ registryErrors: [RegistryError],
    _ evidenceErrors: [EvidenceError],
  ) -> [JSONObject] {
    let registry = registryErrors.map { error in
      var object = JSONObject([("code", .string(error.code.rawValue))])
      object["line"] = error.line.map { line in
        .number(Double(line))
      }
      object["message"] = .string(error.message)
      object["binding_slug"] = error.bindingSlug.map(JSONValue.string)
      object["row_id"] = error.rowIdentifier.map(JSONValue.string)
      return object
    }
    let evidence = evidenceErrors.map { error in
      var object = JSONObject([("code", .string(error.code.rawValue))])
      object["line"] = error.line.map { line in
        .number(Double(line))
      }
      object["message"] = .string(error.message)
      object["event_id"] = error.eventIdentifier.map(JSONValue.string)
      return object
    }
    return registry + evidence
  }

  /// Each row's verification context hash recomputed from the current
  /// verifiers, declared inputs and lockfile.
  private static func currentContextHashes(
    _ options: ScanCommandOptions,
    loaded: LoadedMarkerRows,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> [(rowIdentifier: String, contextHash: String)] {
    let root = options.repositoryWorkingDirectory ?? options.productRoot
    var hashes: [(rowIdentifier: String, contextHash: String)] = []
    for row in loaded.rows {
      do throws(VerificationContextHashError) {
        let hash = try VerificationContextHash.computeForRow(
          slug: row.rowIdentifier,
          verificationPolicy: row.verificationPolicy,
          rootDirectory: root,
          files: files,
          workspaceVerifiers: options.context.verifiers,
        )
        hashes.append((row.rowIdentifier, hash))
      } catch {
        throw .verificationContextHash(error)
      }
    }
    return hashes
  }

  /// The results ledger at the override or its conventional path, then the run
  /// key; an absent ledger yields no results.
  private static func localResults(
    _ options: ScanCommandOptions,
    files: some MarkerFileSystem,
    runKeyLocation: RunKeyLocation,
  ) throws(MarkerCommandError) -> [LocalVerificationResult] {
    let resultsPath = options.resultsPath ?? NodePath.join(
      options.context.dataRoot,
      ".use-cases",
      LocalVerificationResults.defaultFilename,
    )
    let resultsText = try readText(resultsPath, files: files)
    let runKey: String?
    do throws(FileAccessError) {
      runKey = try RunAttestation.readLocalRunKey(
        keyPath: options.runKeyPath ?? runKeyLocation.defaultPath,
        files: files,
      )
    } catch {
      throw .fileAccess(error)
    }
    guard let resultsText else {
      return []
    }
    do throws(CodeUnitCanonicalJSONError) {
      return try LocalVerificationResults.parse(resultsText, runKey: runKey)
    } catch {
      throw .canonicalJSON(error)
    }
  }

  private static func readText(
    _ path: String,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> String? {
    do throws(FileAccessError) {
      return try files.readText(atPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }
}
