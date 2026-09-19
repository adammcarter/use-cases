import Foundation

/// The one place a black-box test learns where the CLI binary is.
///
/// This is the Swift half of the TypeScript oracle's `uc-binary` helper, and it
/// keeps that file's seam: `UC_BIN`, unset, runs the Swift build sitting in
/// `UseCasesCLI/.build`; set, it runs whatever it names. That is how a CI job
/// points the oracle at the binary it just built rather than at a stale one,
/// and it is how row 10a ran this suite against the TypeScript bundle and the
/// Swift build in turn to prove the port had not quietly weakened an assertion.
/// The bundle is gone (ADR 0007 row 10d); the seam is not.
///
/// The one thing it must never do is fall back. A harness that answered "the
/// binary you named is missing, here is the other one" would keep every test
/// passing while testing something nobody asked for; `HarnessTests` pins that
/// it refuses instead.
struct CliBinary: Sendable {
  /// The executable, plus any arguments that must lead every invocation.
  let command: String
  let leadingArguments: [String]
  /// True when `UC_BIN` named it, i.e. we are NOT testing the default build.
  let overridden: Bool

  static let environmentVariable = "UC_BIN"

  /// Resolve from the process environment, the way the TypeScript helper does.
  static func resolved() throws -> CliBinary {
    try resolved(override: ProcessInfo.processInfo.environment[environmentVariable])
  }

  /// The resolution rule itself, with the environment passed in.
  ///
  /// The TypeScript harness test mutates `process.env.UC_BIN` around each case.
  /// Swift Testing runs tests in parallel in one process, where `setenv` is
  /// both unsafe and visible to every other test, so the override is a
  /// parameter here and `resolved()` is the thin reader over it.
  static func resolved(override: String?) throws -> CliBinary {
    let named = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !named.isEmpty {
      guard FileManager.default.isExecutableFile(atPath: named) else {
        throw OracleFailure.binaryUnusable(variable: environmentVariable, path: named)
      }
      return CliBinary(command: named, leadingArguments: [], overridden: true)
    }
    guard let built = OracleLayout.builtBinary(package: "UseCasesCLI", named: "use-cases") else {
      throw OracleFailure.binaryMissing(
        name: "use-cases",
        searched: OracleLayout.buildDirectories(package: "UseCasesCLI"),
        variable: environmentVariable,
      )
    }
    return CliBinary(command: built, leadingArguments: [], overridden: false)
  }

  /// What one run of the CLI produced. A nonzero exit is a result, not an
  /// error: plenty of behaviours under test are refusals and their exit code is
  /// part of what the scenario asserts.
  struct Outcome: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    /// The pid of the process that was spawned. `RuntimeResolverTests` compares
    /// it against the pid the executable REPORTS: they are equal only when every
    /// wrapper in `bin/` exec'd, leaving no shell holding the server's pipes.
    var processIdentifier: Int32 = 0
  }

  /// The v1 result envelope every `--json` command emits.
  struct Envelope: Sendable {
    let json: OracleJson

    var schemaVersion: Int? {
      json["schema_version"]?.intValue
    }

    var protocolVersion: Int? {
      json["protocol_version"]?.intValue
    }

    var command: String? {
      json["command"]?.stringValue
    }

    /// The envelope's `ok`. Named `isOk` because a two-letter identifier is a
    /// lint violation, not because the wire key differs.
    var isOk: Bool? {
      json["ok"]?.boolValue
    }

    var complete: Bool? {
      json["complete"]?.boolValue
    }

    var data: OracleJson {
      json["data"] ?? .null
    }

    var diagnostics: OracleJson {
      json["diagnostics"] ?? .null
    }

    var context: OracleJson {
      json["context"] ?? .null
    }

    /// The diagnostic codes, in order — the shape most assertions want.
    var diagnosticCodes: [String] {
      (diagnostics.arrayValue ?? []).compactMap { entry in
        entry["code"]?.stringValue
      }
    }
  }

  struct JsonOutcome: Sendable {
    let envelope: Envelope
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var data: OracleJson {
      envelope.data
    }

    var isOk: Bool? {
      envelope.isOk
    }

    var diagnosticCodes: [String] {
      envelope.diagnosticCodes
    }
  }

  /// Run the CLI and hand back the raw result. Never throws on a nonzero exit.
  func run(
    _ arguments: [String],
    cwd: String? = nil,
    environment: [String: String] = [:],
  ) async throws -> Outcome {
    try await OracleProcess.run(
      executable: command,
      arguments: leadingArguments + arguments,
      cwd: cwd ?? OracleLayout.repositoryRoot,
      environment: environment,
    )
  }

  /// Run the CLI with `--json` and parse the envelope.
  ///
  /// Only unparseable stdout throws, and it throws with the stderr attached,
  /// because a bare "Unexpected token" tells the reader nothing about which
  /// command broke.
  func runJson(
    _ arguments: [String],
    cwd: String? = nil,
    environment: [String: String] = [:],
  ) async throws -> JsonOutcome {
    let outcome = try await run(arguments + ["--json"], cwd: cwd, environment: environment)
    guard let parsed = try? OracleJson.parse(outcome.standardOutput) else {
      throw OracleFailure.unparseableStdout(
        arguments: arguments,
        exitCode: outcome.exitCode,
        standardOutput: outcome.standardOutput,
        standardError: outcome.standardError,
      )
    }
    return JsonOutcome(
      envelope: Envelope(json: parsed),
      exitCode: outcome.exitCode,
      standardOutput: outcome.standardOutput,
      standardError: outcome.standardError,
    )
  }
}

/// Everything the oracle can refuse to do.
enum OracleFailure: Error, CustomStringConvertible {
  case binaryMissing(name: String, searched: [String], variable: String)
  case binaryUnusable(variable: String, path: String)
  case unparseableStdout(
    arguments: [String],
    exitCode: Int32,
    standardOutput: String,
    standardError: String,
  )
  case requestTimedOut(method: String, seconds: Int)
  case serverEnded(method: String)

  var description: String {
    switch self {
    case let .binaryMissing(name, searched, variable):
      """
      no built \(name) binary — looked in \(searched.joined(separator: ", ")). \
      Build it, or name one with \(variable).
      """
    case let .binaryUnusable(variable, path):
      "\(variable)=\(path) is not an executable file"
    case let .unparseableStdout(arguments, exitCode, standardOutput, standardError):
      """
      use-cases \(arguments.joined(separator: " ")) --json: stdout did not parse \
      as JSON (exit \(exitCode))
      stdout: \(standardOutput.isEmpty ? "(empty)" : standardOutput)
      stderr: \(standardError.isEmpty ? "(empty)" : standardError)
      """
    case let .requestTimedOut(method, seconds):
      "MCP \(method) timed out after \(seconds)s"
    case let .serverEnded(method):
      "the MCP server ended before answering \(method)"
    }
  }
}

/// Where things are, relative to this file.
enum OracleLayout {
  /// The package directory: four levels up from `Harness/`.
  static let packageRoot = (0 ..< 4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
    url.deletingLastPathComponent()
  }

  /// The repository, which is what a run's default working directory is — the
  /// TypeScript helper defaults to the repo root too, and the roster, skills
  /// and plugin files read the live trees there.
  static let repositoryRoot = packageRoot.deletingLastPathComponent().path

  static func buildDirectories(package: String) -> [String] {
    ["debug", "release"].map { configuration in
      "\(repositoryRoot)/\(package)/.build/\(configuration)"
    }
  }

  static func builtBinary(
    package: String,
    named name: String,
  ) -> String? {
    buildDirectories(package: package)
      .map { directory in
        "\(directory)/\(name)"
      }
      .first { candidate in
        FileManager.default.isExecutableFile(atPath: candidate)
      }
  }
}

/// Running one process to completion, without a pipe that can fill.
///
/// Both streams go to files under a private temporary directory, so nothing has
/// to be read while the process runs — a `scan` over a thousand rows outruns a
/// 64KB pipe buffer, and a reader that is not draining it deadlocks.
enum OracleProcess {
  /// `inheritEnvironment: false` runs with EXACTLY the environment passed in.
  /// The bootstrap suites need that: their whole hermeticity rests on every
  /// `USE_CASES_*` variable and `XDG_CACHE_HOME` being absent, and a merge over
  /// the test process's own environment cannot express an absence.
  static func run(
    executable: String,
    arguments: [String],
    cwd: String,
    environment: [String: String],
    inheritEnvironment: Bool = true,
  ) async throws -> CliBinary.Outcome {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("use-cases-oracle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: scratch)
    }

    let outputURL = scratch.appendingPathComponent("stdout")
    let errorURL = scratch.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    process.environment = inheritEnvironment ? inherited(environment) : environment
    process.standardOutput = try FileHandle(forWritingTo: outputURL)
    process.standardError = try FileHandle(forWritingTo: errorURL)

    let (terminations, termination) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { finished in
      termination.yield(finished.terminationStatus)
      termination.finish()
    }
    try process.run()
    let pid = process.processIdentifier
    var exitCode: Int32 = -1
    for await status in terminations {
      exitCode = status
    }
    return CliBinary.Outcome(
      exitCode: exitCode,
      standardOutput: (try? String(contentsOf: outputURL, encoding: .utf8)) ?? "",
      standardError: (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "",
      processIdentifier: pid,
    )
  }

  /// The test process's environment with the caller's overrides on top, which
  /// is what `spawnSync`'s `{ ...process.env, ...env }` does.
  ///
  /// `LLVM_PROFILE_FILE` is pinned aside because a debug Swift build is
  /// instrumented, and a hundred oracle processes writing one `default.profraw`
  /// in the repository would race over that instead of testing anything.
  static func inherited(_ overrides: [String: String]) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["LLVM_PROFILE_FILE"] = "/dev/null"
    for (key, value) in overrides {
      environment[key] = value
    }
    return environment
  }
}
