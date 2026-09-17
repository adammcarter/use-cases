import UseCasesCore

/// `prove`: mint signed proofs from the unsigned results ledger `verify` wrote.
/// Its file inputs are read and refused (exit 2) before the core runs.
extension MarkersCommands {
  static func runProve(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.prove"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    guard runtime.isOn("all") || runtime.truthy("row") != nil else {
      return invalidArguments(command, "Missing --row or --all.")
    }
    let inputs: (results: [JSONValue]?, authority: JSONValue)
    switch readInputs(runtime, command: command) {
    case let .refused(output):
      return output
    case let .read(read):
      inputs = read
    }
    let paths = runtime.paths(workspace)
    var options = try ProveCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: runtime.publicKeyResolver(),
      generatedAt: runtime.string("generatedAt") ?? currentTimestamp(),
      identifierFactory: MarkerEventIdentifier.generate,
    )
    applyModeFlags(runtime, to: &options)
    options.verificationResults = inputs.results
    options.unsafeAssumeVerificationPassed =
      runtime.string("unsafeAssumeVerificationResult") == "pass"
    options.signingKey = try runtime.signingKey()
    options.producer = runtime.producer
    options.authority = inputs.authority
    options.baseReference = runtime.string("baseRef")
    options.repositoryWorkingDirectory = workspace.workspaceRoot

    let result = try prove(options, runtime: runtime)
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  /// What to prove and how: the target, and the refresh, trust, append and
  /// dry-run switches.
  private static func applyModeFlags(
    _ runtime: MarkerRuntime,
    to options: inout ProveCommandOptions,
  ) {
    options.rowIdentifier = runtime.string("row")
    options.all = runtime.isOn("all")
    options.refresh = runtime.isOn("refresh")
    options.trustedContinuousIntegration = runtime.isOn("trustedCi")
    options.append = runtime.isOn("append")
    options.dryRun = runtime.isOn("dryRun")
  }

  /// The core prove with this run's git, run key, environment and registry;
  /// shared with `recover`.
  static func prove(
    _ options: ProveCommandOptions,
    runtime: MarkerRuntime,
  ) throws(CommandFailure) -> ProveCommandResult {
    let registry = try SchemaRegistryLoader.load()
    do throws(MarkerCommandError) {
      return try ProveCommand.run(
        options,
        registry: registry,
        gitRunner: runtime.gitRunner,
        runKeyLocation: runtime.runKeyLocation,
        environment: runtime.environment,
      )
    } catch {
      throw CommandFailure(error)
    }
  }

  private enum FileInput<Value> {
    case read(Value)
    case refused(CommandOutput)
  }

  /// The results ledger when named, then the authority: an explicit record
  /// wins, otherwise it is detected from the environment.
  private static func readInputs(
    _ runtime: MarkerRuntime,
    command: String,
  ) -> FileInput<(results: [JSONValue]?, authority: JSONValue)> {
    var results: [JSONValue]?
    if let resultsFlag = runtime.truthy("verificationResults") {
      switch readResults(runtime.resolved(resultsFlag), command: command) {
      case let .refused(output):
        return .refused(output)
      case let .read(records):
        results = records
      }
    }
    guard let authorityFlag = runtime.truthy("authorityFile") else {
      return .read((results, runtime.detectedAuthority))
    }
    switch readAuthority(runtime.resolved(authorityFlag), command: command) {
    case let .refused(output):
      return .refused(output)
    case let .read(record):
      return .read((results, record))
    }
  }

  /// One JSON value per non-blank line, each line trimmed first.
  private static func readResults(
    _ path: String,
    command: String,
  ) -> FileInput<[JSONValue]> {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      return .refused(invalidArguments(
        command,
        "Could not read --verification-results file: \(path)",
      ))
    }
    var records: [JSONValue] = []
    for line in JavaScriptString.split(text, on: 0x0A) {
      let trimmed = JavaScriptString.trim(line)
      guard !trimmed.isEmpty else {
        continue
      }
      do throws(SchemaError) {
        try records.append(JSONParser.parse(trimmed))
      } catch {
        return .refused(invalidArguments(
          command,
          "--verification-results file is not valid JSONL: \(path)",
        ))
      }
    }
    return .read(records)
  }

  private static func readAuthority(
    _ path: String,
    command: String,
  ) -> FileInput<JSONValue> {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      return .refused(invalidArguments(command, "Could not read --authority-file: \(path)"))
    }
    do throws(SchemaError) {
      return try .read(JSONParser.parse(text))
    } catch {
      return .refused(invalidArguments(command, "--authority-file is not valid JSON: \(path)"))
    }
  }
}
