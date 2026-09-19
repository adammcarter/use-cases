import UseCasesCore

/// `scan`, `impact`, `verify` and `validate-ledger`: the read-and-verify side of
/// the marker commands, each handing its core the workspace root as the
/// directory git and the verifiers run in.
extension MarkersCommands {
  static func runScan(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.scan"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    let paths = runtime.paths(workspace)
    let policyMode = PolicyMode(rawValue: runtime.string("policyMode") ?? "feature") ?? .feature
    var options = try ScanCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      policyMode: policyMode,
      publicKeyResolver: runtime.publicKeyResolver(),
      generatedAt: runtime.string("generatedAt") ?? currentTimestamp(),
    )
    options.trustedKeyConfigured = runtime.isKeyConfigured
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    options.resultsPath = runtime.truthy("results").map(runtime.resolved)
    options.gate = runtime.isOn("gate")

    let registry = try SchemaRegistryLoader.load()
    let result: ScanCommandResult
    do throws(MarkerCommandError) {
      result = try ScanCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
        runKeyLocation: runtime.runKeyLocation,
      )
    } catch {
      throw CommandFailure(error)
    }
    // CI mode prints the inferred spans to stderr, a log side channel beside
    // the envelope.
    if runtime.isOn("ci"), !result.inferredSpans.isEmpty {
      context.standardError.append(result.inferredSpans.joined(separator: "\n\n") + "\n")
    }
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  static func runImpact(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.impact"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    let paths = runtime.paths(workspace)
    var options = try ImpactCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: runtime.publicKeyResolver(),
      generatedAt: runtime.string("generatedAt") ?? currentTimestamp(),
    )
    options.base = runtime.string("base")
    options.staged = runtime.isOn("staged")
    options.repositoryWorkingDirectory = workspace.workspaceRoot

    let registry = try SchemaRegistryLoader.load()
    let result: ImpactCommandResult
    do throws(MarkerCommandError) {
      result = try ImpactCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
        runKeyLocation: runtime.runKeyLocation,
      )
    } catch {
      throw CommandFailure(error)
    }
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  static func runVerify(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.verify"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    guard runtime.isOn("all") || runtime.truthy("row") != nil else {
      return invalidArguments(command, "Missing --all or --row <slug>.")
    }
    let paths = runtime.paths(workspace)
    // The unsigned results ledger defaults to where `scan` looks for it, so
    // `verify` then `scan` closes the keyless loop with no flags.
    let outPath = runtime.truthy("out").map(runtime.resolved)
      ?? NodePath.join(workspace.dataRoot, ".use-cases", "verification-results.jsonl")
    var options = try VerifyCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: runtime.publicKeyResolver(),
      generatedAt: runtime.string("generatedAt") ?? currentTimestamp(),
    )
    options.trustedKeyConfigured = runtime.isKeyConfigured
    options.all = runtime.isOn("all")
    options.rowIdentifier = runtime.string("row")
    options.outPath = outPath
    options.dryRun = runtime.isOn("dryRun")
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot

    let result = try verify(options, runtime: runtime)
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  static func runValidateLedger(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.validate-ledger"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    let paths = runtime.paths(workspace)
    var options = try ValidateLedgerCommandOptions(
      context: workspace,
      evidencePath: paths.evidencePath,
      bindingsPath: paths.bindingsPath,
      publicKeyResolver: runtime.publicKeyResolver(),
    )
    // At the CLI the ledger paths are absolute, which `git show <ref>:<path>`
    // never finds, so the base reads as empty and the append-only check passes
    // (docs/rewrite/ladder-notes.md, "Found reading d4"). Kept as it is.
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot

    let registry = try SchemaRegistryLoader.load()
    let result: ValidateLedgerCommandResult
    do throws(MarkerCommandError) {
      result = try ValidateLedgerCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
      )
    } catch {
      throw CommandFailure(error)
    }
    // `ok`, not the exit code, decides the envelope here.
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.isOK,
      workspace: workspace,
    )
  }

  /// The core verify with this run's git, run key and registry; shared with
  /// `recover`.
  static func verify(
    _ options: VerifyCommandOptions,
    runtime: MarkerRuntime,
  ) throws(CommandFailure) -> VerifyCommandResult {
    let registry = try SchemaRegistryLoader.load()
    do throws(MarkerCommandError) {
      return try VerifyCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
        runKeyLocation: runtime.runKeyLocation,
      )
    } catch {
      throw CommandFailure(error)
    }
  }
}
