/// Running one command step and describing what it did
/// (`runCommandStep`, `commandObservationText`).
extension DemoCapsuleRunner {
  /// Captured output is cut to this many UTF-16 code units.
  static let largestCapturedOutput = 16384

  /// The command run with the allowlisted environment, its output redacted
  /// and then cut; node's spawn error stands in for a stderr that never
  /// existed.
  func execute(
    _ command: DemoCapsuleCommandStep,
    _ entry: DemoCapsulePlannedStep,
    workingDirectory: String,
    options: DemoCapsuleRunOptions,
  ) throws(DemoCapsuleError) -> DemoCapsuleCommandResult {
    let outcome: CapsuleSpawnOutcome
    do throws(CapsuleSpawnError) {
      outcome = try spawner.spawn(CapsuleSpawnRequest(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: workingDirectory,
        environment: commandEnvironment,
        timeoutMilliseconds: options.commandTimeoutMilliseconds,
      ))
    } catch {
      throw .spawn(error)
    }
    return DemoCapsuleCommandResult(
      itemIndex: entry.itemIndex,
      stepIndex: entry.stepIndex,
      useCaseIdentifier: entry.useCaseIdentifier,
      step: command,
      exitCode: outcome.exitStatus,
      signal: outcome.signal,
      standardOutput: Self.sanitized(outcome.standardOutput ?? ""),
      standardError: Self.sanitized(outcome.standardError ?? outcome.errorMessage ?? ""),
    )
  }

  /// `commandEnvironment`: each allowlisted variable that is defined, in
  /// allowlist order.
  var commandEnvironment: [String] {
    Self.allowlistedVariables.compactMap { name in
      environment[name].map { value in
        "\(name)=\(value)"
      }
    }
  }

  /// The observation a command step records.
  static func observationText(_ result: DemoCapsuleCommandResult) -> String {
    let exit = result.exitCode.map(String.init) ?? "null"
    let signal = result.signal.flatMap { name in
      name.isEmpty ? nil : " with signal \(name)"
    } ?? ""
    let codes = result.step.expectedExitCodes.map(JavaScriptNumber.text).joined(separator: ", ")
    return [
      "Command exited \(exit)\(signal).",
      "Expected exit codes: \(codes.isEmpty ? "<none>" : codes).",
      "stdout:\n\(result.standardOutput.isEmpty ? "<empty>" : result.standardOutput)",
      "stderr:\n\(result.standardError.isEmpty ? "<empty>" : result.standardError)",
    ].joined(separator: "\n")
  }

  /// `sanitizeCommandOutput`: redacted, then cut. A cut through a surrogate
  /// pair leaves U+FFFD where the TypeScript keeps a lone surrogate.
  private static func sanitized(_ value: String) -> String {
    let units = Array(Redactor.redactSecrets(value).utf16)
    guard units.count > largestCapturedOutput else {
      return CodeUnits.string(units)
    }
    return CodeUnits.string(units[0 ..< largestCapturedOutput]) + "\n[truncated]"
  }
}
