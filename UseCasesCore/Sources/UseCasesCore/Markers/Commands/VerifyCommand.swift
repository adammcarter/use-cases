public struct VerifyCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var evidencePath: String
  public var publicKeyResolver: PublicKeyResolver
  /// See ``ScanCommandOptions/trustedKeyConfigured``. verify never consumes
  /// signed proofs, so without a configured key a missing key never blocks it.
  public var trustedKeyConfigured: Bool?
  public var generatedAt: String
  /// Every bound row, or — when set and non-empty — one row.
  public var all: Bool
  public var rowIdentifier: String?
  /// When set and non-empty, the results ledger is merged into this file.
  public var outPath: String?
  /// Plan what would run; run nothing, write nothing.
  public var dryRun: Bool
  public var commentConfiguration: CommentPrefixConfiguration?
  public var baseReference: String?
  /// Where verifiers run and context hashes are taken (the product root when
  /// nil).
  public var repositoryWorkingDirectory: String?
  /// The machine-local run key; nil reads the default location.
  public var runKeyPath: String?

  public init(
    context: ResolvedWorkspaceContext,
    productRoot: String,
    bindingsPath: String,
    evidencePath: String,
    publicKeyResolver: @escaping PublicKeyResolver,
    generatedAt: String,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.evidencePath = evidencePath
    self.publicKeyResolver = publicKeyResolver
    trustedKeyConfigured = nil
    self.generatedAt = generatedAt
    all = false
    rowIdentifier = nil
    outPath = nil
    dryRun = false
    commentConfiguration = nil
    baseReference = nil
    repositoryWorkingDirectory = nil
    runKeyPath = nil
  }
}

/// `runVerifyCommand`: run each targeted row's resolved verifiers through the
/// spawn runner and record an UNSIGNED, run-attested result per row — per
/// variant for a family. It never signs and never touches the evidence ledger.
public enum VerifyCommand {
  public static func run(
    _ options: VerifyCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
    gitRunner: some GitRunning = GitProcessRunner(),
    spawnRunner: some VerifySpawnRunning = VerifyProcessRunner(),
    runKeyLocation: RunKeyLocation = .process,
  ) throws(MarkerCommandError) -> VerifyCommandResult {
    let rowIdentifier = options.rowIdentifier.flatMap { $0.isEmpty ? nil : $0 }
    guard options.all || rowIdentifier != nil else {
      return VerifyCommandResult(exitCode: 2, errors: [MarkerCommandFailure(
        code: "NO_TARGET",
        message: "verify requires --all or --row <slug>",
      )])
    }
    let prepared = try ScanCommand.prepare(
      scanOptions(options),
      files: files,
      registry: registry,
      gitRunner: gitRunner,
      runKeyLocation: runKeyLocation,
    )
    // Only real corruption blocks: a signed proof nobody holds a key for is
    // not a reason to stop verifying.
    guard prepared.registryErrors.isEmpty, prepared.evidenceIntegrityErrors.isEmpty else {
      return VerifyCommandResult(exitCode: 4, errors: ledgerInvalidFailures(prepared))
    }
    guard let targets = targets(prepared, rowIdentifier: rowIdentifier) else {
      return VerifyCommandResult(exitCode: 2, errors: [MarkerCommandFailure(
        code: "ROW_NOT_FOUND",
        message: "row \(rowIdentifier ?? "") is not a known use-case row",
      )])
    }
    var run = VerifyRun(
      options: options,
      prepared: prepared,
      contextRoot: options.repositoryWorkingDirectory ?? options.productRoot,
    )
    if options.dryRun {
      return run.plan(targets)
    }
    try run.verify(targets, files: files, spawnRunner: spawnRunner)
    try run.attest(files: files, runKeyLocation: runKeyLocation)
    return try run.finish(files: files)
  }

  /// Every bound row in code-unit order, or the one named row — none when it
  /// is unbound. Nil when the named row is not a known row.
  private static func targets(
    _ prepared: ScanPreparation,
    rowIdentifier: String?,
  ) -> [String]? {
    guard let rowIdentifier else {
      return JavaScriptString.sorted(prepared.status.rows.filter { row in
        row.status != .unbound
      }.map(\.rowIdentifier))
    }
    guard let target = TargetRow(rowIdentifier, in: prepared) else {
      return nil
    }
    return target.status.status == .unbound ? [] : [rowIdentifier]
  }

  private static func scanOptions(_ options: VerifyCommandOptions) -> ScanCommandOptions {
    var scan = ScanCommandOptions(
      context: options.context,
      productRoot: options.productRoot,
      bindingsPath: options.bindingsPath,
      evidencePath: options.evidencePath,
      policyMode: .feature,
      publicKeyResolver: options.publicKeyResolver,
      generatedAt: options.generatedAt,
    )
    scan.trustedKeyConfigured = options.trustedKeyConfigured
    scan.commentConfiguration = options.commentConfiguration
    scan.baseReference = options.baseReference
    scan.repositoryWorkingDirectory = options.repositoryWorkingDirectory
    return scan
  }

  /// LEDGER_INVALID, then every registry and evidence integrity error, each
  /// message prefixed with its line when it has one.
  private static func ledgerInvalidFailures(_ prepared: ScanPreparation) -> [MarkerCommandFailure] {
    let lined = { (line: Int?, message: String) in
      line.map { number in
        "line \(number): \(message)"
      } ?? message
    }
    return [MarkerCommandFailure(
      code: "LEDGER_INVALID",
      message: "registry or evidence ledger failed validation",
    )]
      + prepared.registryErrors.map { error in
        MarkerCommandFailure(code: error.code.rawValue, message: lined(error.line, error.message))
      }
      + prepared.evidenceIntegrityErrors.map { error in
        MarkerCommandFailure(code: error.code.rawValue, message: lined(error.line, error.message))
      }
  }
}
