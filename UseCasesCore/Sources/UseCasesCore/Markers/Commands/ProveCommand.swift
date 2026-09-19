import Foundation

public struct ProveCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var evidencePath: String
  public var publicKeyResolver: PublicKeyResolver
  /// One row when set and non-empty; otherwise `all` sweeps every row.
  public var rowIdentifier: String?
  public var all: Bool
  /// Re-sign rows that are already FRESH.
  public var refresh: Bool
  public var trustedContinuousIntegration: Bool
  /// An explicit append request; untrusted, it is refused with exit 6.
  public var append: Bool
  public var dryRun: Bool
  /// The consumed results ledger, one parsed JSON value per line, exactly as
  /// the caller read it: prove reads each value as the TypeScript reads an
  /// unchecked cast, so a line of the wrong shape behaves as it does there.
  public var verificationResults: [JSONValue]?
  /// DANGEROUS: assume the row's verification passed. Honoured only when the
  /// environment sets `UCM_ALLOW_UNSAFE_VERIFICATION` to exactly `1`.
  public var unsafeAssumeVerificationPassed: Bool
  public var signingKey: ProveSigningKey?
  public var producer: ProveProducer?
  /// The CI-neutral authority embedded, before signing, when it is truthy.
  /// ``ProveCommand/authorityRecord(_:)`` spells a detected one; a record
  /// read from a file is passed as the JSON it is.
  public var authority: JSONValue?
  public var generatedAt: String
  public var identifierFactory: () -> String
  public var commentConfiguration: CommentPrefixConfiguration?
  public var baseReference: String?
  /// Where `git show` runs and context hashes are taken (the product root
  /// when nil).
  public var repositoryWorkingDirectory: String?

  public init(
    context: ResolvedWorkspaceContext,
    productRoot: String,
    bindingsPath: String,
    evidencePath: String,
    publicKeyResolver: @escaping PublicKeyResolver,
    generatedAt: String,
    identifierFactory: @escaping () -> String = ProveCommand.generateEventIdentifier,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.evidencePath = evidencePath
    self.publicKeyResolver = publicKeyResolver
    rowIdentifier = nil
    all = false
    refresh = false
    trustedContinuousIntegration = false
    append = false
    dryRun = false
    verificationResults = nil
    unsafeAssumeVerificationPassed = false
    signingKey = nil
    producer = nil
    authority = nil
    self.generatedAt = generatedAt
    self.identifierFactory = identifierFactory
    commentConfiguration = nil
    baseReference = nil
    repositoryWorkingDirectory = nil
  }
}

/// `runProveCommand` (spec 8.3): consume the unsigned results ledger, recompute
/// every hash, and — trusted, with a key — append a signed proof for each row
/// whose latest result passed with matching hashes. Appends are NOT atomic: a
/// passing row is appended even when a sibling fails, and the run exits 5.
public enum ProveCommand {
  /// The variable that must be exactly `1` for the unsafe seam to be honoured.
  public static let allowUnsafeVerificationVariable = "UCM_ALLOW_UNSAFE_VERIFICATION"

  public static func run(
    _ options: ProveCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
    runKeyLocation: RunKeyLocation = .process,
    environment: [String: String] = ProcessInfo.processInfo.environment,
  ) throws(MarkerCommandError) -> ProveCommandResult {
    let trusted = options.trustedContinuousIntegration
    let rowIdentifier = options.rowIdentifier.flatMap { $0.isEmpty ? nil : $0 }
    if options.append, !trusted {
      return refusal(
        6,
        trusted: false,
        "UNTRUSTED_APPEND",
        "an append was requested without trusted-CI credentials",
      )
    }
    guard options.all || rowIdentifier != nil else {
      return refusal(2, trusted: trusted, "NO_TARGET", "prove requires --all or --row <slug>")
    }
    let prepared = try ScanCommand.prepare(
      scanOptions(options),
      files: files,
      registry: registry,
      gitRunner: gitRunner,
      runKeyLocation: runKeyLocation,
    )
    if let refused = refusalAfterScan(options, prepared: prepared, rowIdentifier: rowIdentifier) {
      return refused
    }
    let allowUnsafe = environment[allowUnsafeVerificationVariable].map { value in
      JavaScriptString.identical(value, "1")
    } ?? false
    let evaluation = ProveRowEvaluation(
      options: options,
      prepared: prepared,
      contextRoot: options.repositoryWorkingDirectory ?? options.productRoot,
      appendKey: trusted && !options.dryRun ? options.signingKey : nil,
      allowUnsafe: allowUnsafe,
      sweep: rowIdentifier == nil,
    )
    let targets = rowIdentifier.map { [$0] }
      ?? JavaScriptString.sorted(prepared.status.rows.map(\.rowIdentifier))
    var rows: [ProveRowResult] = []
    for target in targets {
      try rows.append(evaluation.prove(target, files: files))
    }
    let anyFailed = rows.contains { row in
      row.status == .failed
    }
    return ProveCommandResult(exitCode: anyFailed ? 5 : 0, trusted: trusted, rows: rows)
  }

  /// The refusals that need the scan, in the TypeScript's order. Stricter
  /// than verify: prove consumes signed proofs, so every evidence error
  /// blocks, a missing key included. A run that will append needs its key
  /// before any row is tried.
  private static func refusalAfterScan(
    _ options: ProveCommandOptions,
    prepared: ScanPreparation,
    rowIdentifier: String?,
  ) -> ProveCommandResult? {
    let trusted = options.trustedContinuousIntegration
    guard prepared.registryErrors.isEmpty, prepared.evidenceErrors.isEmpty else {
      return refusal(
        4,
        trusted: trusted,
        "LEDGER_INVALID",
        "registry or evidence ledger failed validation",
      )
    }
    if trusted, !options.dryRun, options.signingKey == nil {
      return refusal(
        2,
        trusted: trusted,
        "SIGNING_KEY_MISSING",
        "trusted-CI prove requires a signing key",
      )
    }
    if let rowIdentifier, TargetRow(rowIdentifier, in: prepared) == nil {
      return refusal(
        2,
        trusted: trusted,
        "ROW_NOT_FOUND",
        "row \(rowIdentifier) is not a known use-case row",
      )
    }
    return nil
  }

  private static func refusal(
    _ exitCode: Int,
    trusted: Bool,
    _ code: String,
    _ message: String,
  ) -> ProveCommandResult {
    ProveCommandResult(
      exitCode: exitCode,
      trusted: trusted,
      errors: [MarkerCommandFailure(code: code, message: message)],
    )
  }

  /// A detected authority as the JSON a proof embeds.
  public static func authorityRecord(_ authority: CiAuthority) -> JSONValue {
    authority.jsonValue
  }

  /// A 26-character Crockford base32 id, ULID-shaped but random: uniqueness
  /// is all it is for. Inject `identifierFactory` for a known id.
  public static func generateEventIdentifier() -> String {
    let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    var generator = SystemRandomNumberGenerator()
    return String((0 ..< 26).map { _ in
      alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)]
    })
  }

  private static func scanOptions(_ options: ProveCommandOptions) -> ScanCommandOptions {
    var scan = ScanCommandOptions(
      context: options.context,
      productRoot: options.productRoot,
      bindingsPath: options.bindingsPath,
      evidencePath: options.evidencePath,
      policyMode: .feature,
      publicKeyResolver: options.publicKeyResolver,
      generatedAt: options.generatedAt,
    )
    scan.commentConfiguration = options.commentConfiguration
    scan.baseReference = options.baseReference
    scan.repositoryWorkingDirectory = options.repositoryWorkingDirectory
    return scan
  }
}
