import UseCasesCore

/// `recover --row <id> | --all`: re-verify (writing the canonical results
/// ledger), stop on a genuine failure, optionally re-prove to FRESH, re-scan,
/// and succeed only when every target reached the bar. It composes the existing
/// cores and adds no trust logic.
extension RecoverCommands {
  static func run(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.recover"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    let all = runtime.isOn("all")
    let rowIdentifier = runtime.string("row")
    guard all || runtime.truthy("row") != nil else {
      return MarkersCommands.invalidArguments(command, "Missing --row <id> or --all.")
    }
    let paths = runtime.paths(workspace)
    let publicKeyResolver = try runtime.publicKeyResolver()
    let recovery = Recovery(
      command: command,
      workspace: workspace,
      runtime: runtime,
      paths: paths,
      publicKeyResolver: publicKeyResolver,
      generatedAt: runtime.string("generatedAt") ?? MarkersCommands.currentTimestamp(),
      all: all,
      rowIdentifier: rowIdentifier,
    )

    // A detectable usage error must not have side effects: the signing key is
    // checked before the verifier runs or the ledger is written.
    let signingKey = try runtime.signingKey()
    if let name = runtime.string("signingKeyEnv"), signingKey == nil {
      return MarkersCommands.invalidArguments(
        command,
        "--signing-key-env \(name) is set but $\(name) is empty — provide the PKCS8 ed25519 "
          + "private key PEM in that env var (a CI secret).",
      )
    }
    return try recovery.recover(signingKey: signingKey)
  }
}

/// One recover run's inputs and its steps.
private struct Recovery {
  let command: String
  let workspace: ResolvedWorkspaceContext
  let runtime: MarkerRuntime
  let paths: MarkerPaths
  let publicKeyResolver: PublicKeyResolver
  let generatedAt: String
  let all: Bool
  let rowIdentifier: String?

  /// The canonical unsigned results ledger `scan` auto-discovers.
  var resultsPath: String {
    NodePath.join(workspace.dataRoot, ".use-cases", LocalVerificationResults.defaultFilename)
  }

  var targetLabel: String {
    all ? "--all" : rowIdentifier ?? "undefined"
  }

  func recover(signingKey: ProveSigningKey?) throws(CommandFailure) -> CommandOutput {
    // 1. Re-run the verifiers, writing the canonical ledger.
    let verified = try MarkersCommands.verify(verifyOptions(), runtime: runtime)

    // 2. A genuine failure stops here, never faked green.
    let failedRows = verified.results.filter { result in
      result.status != .pass
    }.map(\.rowIdentifier)
    if verified.exitCode != 0 || !failedRows.isEmpty {
      return verificationFailure(verified, failedRows: failedRows)
    }

    // 3. Re-prove to FRESH when a signing key was supplied.
    var proved: ProveCommandResult?
    if let signingKey {
      let options = proveOptions(verified, signingKey: signingKey)
      let result = try MarkersCommands.prove(options, runtime: runtime)
      if result.exitCode != 0 {
        return proveFailure(verified, proved: result)
      }
      proved = result
    }

    // 4-5. Re-scan and confirm every target reached the bar.
    let scanned = try scan()
    return confirmation(verified: verified, proved: proved, scanned: scanned)
  }

  private func verifyOptions() -> VerifyCommandOptions {
    var options = VerifyCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: publicKeyResolver,
      generatedAt: generatedAt,
    )
    options.all = all
    options.rowIdentifier = rowIdentifier
    options.outPath = resultsPath
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    return options
  }

  private func proveOptions(
    _ verified: VerifyCommandResult,
    signingKey: ProveSigningKey,
  ) -> ProveCommandOptions {
    var options = ProveCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: publicKeyResolver,
      generatedAt: generatedAt,
      identifierFactory: MarkerEventIdentifier.generate,
    )
    options.rowIdentifier = rowIdentifier
    options.all = all
    options.refresh = true
    options.trustedContinuousIntegration = true
    options.append = true
    options.verificationResults = verified.results.map(\.jsonValue)
    options.signingKey = signingKey
    options.producer = runtime.producer
    options.authority = runtime.detectedAuthority
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    return options
  }

  private func scan() throws(CommandFailure) -> ScanCommandResult {
    var options = ScanCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      policyMode: .feature,
      publicKeyResolver: publicKeyResolver,
      generatedAt: generatedAt,
    )
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    let registry = try SchemaRegistryLoader.load()
    do throws(MarkerCommandError) {
      return try ScanCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
        runKeyLocation: runtime.runKeyLocation,
      )
    } catch {
      throw CommandFailure(error)
    }
  }

  private func verificationFailure(
    _ verified: VerifyCommandResult,
    failedRows: [String],
  ) -> CommandOutput {
    let named = failedRows.isEmpty ? targetLabel : failedRows.joined(separator: ", ")
    let target = all ? "--all" : "--row \(rowIdentifier ?? "undefined")"
    let diagnostic = Diagnostic(
      code: "recover.verification_failed",
      message: "recover could not restore \(named) to green: the verifier failed for \(named). "
        + "Fix the code or the test so the row's verifier passes, then re-run `uc recover`. "
        + "Inspect the failure with `uc verify --repo \(workspace.workspaceRoot) \(target)`.",
      entityIdentifier: failedRows.first ?? rowIdentifier,
      relatedIdentifiers: failedRows,
    )
    let data = JSONValue.object(JSONObject([
      ("recovered", .bool(false)),
      ("proved", .bool(false)),
      ("verify", verified.jsonValue),
      ("failed_rows", .array(failedRows.map(JSONValue.string))),
    ]))
    return failed(data: data, diagnostic: diagnostic, exitCode: 1)
  }

  private func proveFailure(
    _ verified: VerifyCommandResult,
    proved: ProveCommandResult,
  ) -> CommandOutput {
    let diagnostic = Diagnostic(
      code: "recover.prove_failed",
      message: "recover re-verified \(targetLabel) but could not mint a signed proof. "
        + "Check the signing key ($\(runtime.string("signingKeyEnv") ?? "undefined")) and the "
        + "trusted-CI authority.",
      entityIdentifier: rowIdentifier,
    )
    let data = JSONValue.object(JSONObject([
      ("recovered", .bool(false)),
      ("proved", .bool(false)),
      ("verify", verified.jsonValue),
      ("prove", proved.jsonValue),
    ]))
    return failed(data: data, diagnostic: diagnostic, exitCode: 1)
  }

  /// A passing verifier alone is not green: an unreadable signed proof, an
  /// integrity error or an unbound target all surface as not green.
  private func confirmation(
    verified: VerifyCommandResult,
    proved: ProveCommandResult?,
    scanned: ScanCommandResult,
  ) -> CommandOutput {
    let wantsFresh = proved != nil
    let targets = targetRowIdentifiers(verified)
    let notGreen = notGreenTargets(targets, scanned: scanned, wantsFresh: wantsFresh)
    let recovered = scanned.exitCode == 0 && !targets.isEmpty && notGreen.isEmpty

    var data = JSONObject([
      ("recovered", .bool(recovered)),
      ("proved", .bool(wantsFresh)),
      ("target", .string(targetLabel)),
      ("results_path", .string(resultsPath)),
      ("verify", verified.jsonValue),
    ])
    if let proved {
      data["prove"] = proved.jsonValue
    }
    data["status"] = scanned.status.jsonValue

    guard !recovered else {
      return CommandOutput(
        result: CliResult.make(
          command: command,
          data: .object(data),
          workspaceRoot: workspace.workspaceRoot,
          dataRoot: workspace.dataRoot,
          componentIdentifier: workspace.componentIdentifier,
        ),
        exitCode: 0,
      )
    }
    let named = notGreen.isEmpty ? targetLabel : notGreen.joined(separator: ", ")
    let hint = notGreenHint(wantsFresh: wantsFresh, scanned: scanned)
    let diagnostic = Diagnostic(
      code: "recover.not_green",
      message: "recover re-verified \(targetLabel) but \(named) did not reach "
        + "\(wantsFresh ? "FRESH" : "VERIFIED_LOCAL"). \(hint)",
      entityIdentifier: notGreen.first ?? rowIdentifier,
      relatedIdentifiers: notGreen,
    )
    return failed(
      data: .object(data),
      diagnostic: diagnostic,
      exitCode: scanned.exitCode != 0 ? Int32(scanned.exitCode) : 1,
    )
  }

  /// Every family verify recorded, or the one named row. verify records a
  /// variant family per variant (`<family>::<key>`); scan reports the family.
  private func targetRowIdentifiers(_ verified: VerifyCommandResult) -> [String] {
    guard all else {
      return [rowIdentifier ?? ""]
    }
    return unique(verified.results.map { result in
      familyRowIdentifier(result.rowIdentifier)
    })
  }

  /// The targets below the bar: FRESH when re-proved, else FRESH or
  /// VERIFIED_LOCAL.
  private func notGreenTargets(
    _ targets: [String],
    scanned: ScanCommandResult,
    wantsFresh: Bool,
  ) -> [String] {
    targets.filter { target in
      let row = scanned.status.rows.first { row in
        row.rowIdentifier == target
      }
      let isFresh = row?.status == .fresh
      return wantsFresh ? !isFresh : !(isFresh || row?.localTier?.status == .verifiedLocal)
    }
  }

  private func notGreenHint(
    wantsFresh: Bool,
    scanned: ScanCommandResult,
  ) -> String {
    if wantsFresh, runtime.string("publicKey") == nil, runtime.string("keyring") == nil {
      return "To read back the freshly signed proof, also pass --public-key <path> (the public "
        + "half of --signing-key-env)."
    }
    if scanned.exitCode != 0 {
      return "`uc scan` reported an integrity error (exit \(scanned.exitCode)) — resolve it, "
        + "then re-run `uc recover`."
    }
    return "Inspect the current state with `uc scan --repo \(workspace.workspaceRoot)`."
  }

  private func failed(
    data: JSONValue,
    diagnostic: Diagnostic,
    exitCode: Int32,
  ) -> CommandOutput {
    CommandOutput(
      result: CliResult.make(
        command: command,
        data: data,
        isSuccessful: false,
        isComplete: false,
        diagnostics: [diagnostic],
        workspaceRoot: workspace.workspaceRoot,
        dataRoot: workspace.dataRoot,
        componentIdentifier: workspace.componentIdentifier,
      ),
      exitCode: exitCode,
    )
  }

  private func familyRowIdentifier(_ identifier: String) -> String {
    guard let separator = identifier.range(of: "::") else {
      return identifier
    }
    return String(identifier[..<separator.lowerBound])
  }

  /// `[...new Set(values)]`: first occurrences, in order.
  private func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { value in
      seen.insert(value).inserted
    }
  }
}
