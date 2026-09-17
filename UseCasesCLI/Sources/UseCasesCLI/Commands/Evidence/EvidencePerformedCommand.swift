import UseCasesCore

/// What `evidence record --perform` observed (`runPerformedCommand`): the argv
/// it spawned, the exit code, and digests of both output streams.
struct EvidencePerformedCommand: Sendable, Equatable {
  /// `spawnSync` with no `timeout` waits for ever; the spawner needs a whole
  /// number, and this one (`Number.MAX_SAFE_INTEGER` milliseconds) never
  /// arrives.
  static let unboundedTimeoutMilliseconds: Double = 9_007_199_254_740_991

  /// The exit code recorded when there is no status: the program never
  /// started, or a signal ended it.
  static let noStatusExitCode = 127

  let argv: [String]
  let exitCode: Int
  let standardOutputDigest: String
  let standardErrorDigest: String

  /// The argv `--perform` runs: everything after a standalone `--` past the
  /// first token (a leading one is already gone), or nothing.
  static func command(after arguments: [String]) -> [String] {
    guard let separator = arguments.dropFirst().firstIndex(of: "--") else {
      return []
    }
    return Array(arguments[(separator + 1)...])
  }

  /// Spawn the command in `workingDirectory` as `spawnSync(executable, args,
  /// { cwd, encoding: "utf8" })` does: the CLI's own environment, no shell, no
  /// timeout, node's 1 MiB output buffer. A program that cannot start is a
  /// failed run, not a failed command; node's synchronous argument refusals
  /// (a NUL byte) are thrown, as node throws them.
  static func perform(
    executable: String,
    arguments: [String],
    workingDirectory: String,
    environment: [String: String],
    spawner: some CapsuleCommandSpawning = CapsuleProcessSpawner(),
  ) throws(CommandFailure) -> EvidencePerformedCommand {
    let request = CapsuleSpawnRequest(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment.keys.sorted().map { key in
        "\(key)=\(environment[key] ?? "")"
      },
      timeoutMilliseconds: unboundedTimeoutMilliseconds,
    )
    let outcome: CapsuleSpawnOutcome
    do throws(CapsuleSpawnError) {
      outcome = try spawner.spawn(request)
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
    return EvidencePerformedCommand(
      argv: [executable] + arguments,
      exitCode: outcome.exitStatus ?? noStatusExitCode,
      standardOutputDigest: MarkerDigest.sha256(outcome.standardOutput ?? ""),
      standardErrorDigest: MarkerDigest.sha256(outcome.standardError ?? ""),
    )
  }

  /// The argv as the summary and diagnostic spell it: joined by spaces.
  var commandLine: String {
    argv.joined(separator: " ")
  }
}
