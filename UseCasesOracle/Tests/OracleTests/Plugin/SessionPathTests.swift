import Foundation
import Testing

//: @use-case:plugin.install.uc_on_path_in_session
/// The black-box oracle for plugin.install.uc_on_path_in_session — the Swift
/// shape of `tests/plugin/session-path.test.ts`.
///
/// The subjects are `hooks/session-start` (bash) and `bin/use-cases` (bash),
/// driven the way a host drives them: as processes, reading their stdout, their
/// stderr and the file they were asked to write.
struct SessionPathTests {
  static let hook = "\(OracleLayout.repositoryRoot)/hooks/session-start"

  /// The hook with `CLAUDE_PLUGIN_ROOT` pointed at this repository and
  /// `CLAUDE_ENV_FILE` cleared, plus whatever the case sets. A `nil` value
  /// deletes the variable, which is the TypeScript's `undefined`.
  static func runHook(_ extra: [String: String?]) async throws -> CliBinary.Outcome {
    var environment = ProcessInfo.processInfo.environment
    environment["CLAUDE_PLUGIN_ROOT"] = OracleLayout.repositoryRoot
    environment.removeValue(forKey: "CLAUDE_ENV_FILE")
    environment["LLVM_PROFILE_FILE"] = "/dev/null"
    for (key, value) in extra {
      if let value {
        environment[key] = value
      } else {
        environment.removeValue(forKey: key)
      }
    }
    return try await OracleProcess.run(
      executable: "/bin/bash",
      arguments: [hook],
      cwd: OracleLayout.repositoryRoot,
      environment: environment,
      inheritEnvironment: false,
    )
  }

  static func bootstrapContext(_ standardOutput: String) throws -> String {
    let payload = try OracleJson.parse(standardOutput)
    return try #require(payload.at("hookSpecificOutput.additionalContext")?.stringValue)
  }

  @Test
  func `bin-use-cases runs the resolved runtime from any working directory`() async throws {
    let elsewhere = try TemporaryDirectory("cwd")

    let result = try await OracleProcess.run(
      executable: "\(OracleLayout.repositoryRoot)/bin/use-cases",
      arguments: ["version", "--json"],
      cwd: elsewhere.path,
      environment: [:],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    let envelope = try OracleJson.parse(result.standardOutput)
    #expect(envelope["command"]?.stringValue == "version")
  }

  @Test
  func `with CLAUDE_ENV_FILE set the hook prints the bootstrap and exports the plugin bin on PATH`()
    async throws
  {
    let directory = try TemporaryDirectory("session-path")
    let envFile = "\(directory.path)/env.sh"

    let result = try await Self.runHook(["CLAUDE_ENV_FILE": envFile])
    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(try Self.bootstrapContext(result.standardOutput).contains("<EXTREMELY_IMPORTANT>"))

    let exported = try String(contentsOfFile: envFile, encoding: .utf8)
    let exportsPath = exported.split(separator: "\n").contains { line in
      line.hasPrefix("export PATH=\"") && line.hasSuffix("/bin:$PATH\"")
    }
    #expect(exportsPath, Comment(rawValue: exported))
    #expect(exported.contains("\(OracleLayout.repositoryRoot)/bin"))

    // Sourcing the file must make use-cases resolvable.
    let probe = try await OracleProcess.run(
      executable: "/bin/bash",
      arguments: [
        "-c",
        "source \"\(envFile)\" && command -v use-cases && use-cases version --json",
      ],
      cwd: OracleLayout.repositoryRoot,
      environment: [:],
    )
    #expect(probe.exitCode == 0, Comment(rawValue: probe.standardError))
    #expect(probe.standardOutput.contains("\(OracleLayout.repositoryRoot)/bin/use-cases"))
  }

  @Test
  func `with CLAUDE_ENV_FILE unset the hook prints the bootstrap and writes nothing`()
    async throws
  {
    let result = try await Self.runHook(["CLAUDE_ENV_FILE": nil])
    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(try Self.bootstrapContext(result.standardOutput).contains("<EXTREMELY_IMPORTANT>"))
    #expect(result.standardError.isEmpty)
  }

  /// The TypeScript loops over the two host shapes inside one test; the loop is
  /// the parameterisation here, so the two cases are reported separately.
  @Test(arguments: [["CLAUDE_ENV_FILE": nil], ["COPILOT_CLI": "1"]] as [[String: String?]])
  func `the bootstrap ends by naming the absolute path of bin-use-cases on every host`(
    extra: [String: String?],
  ) async throws {
    let result = try await Self.runHook(extra)
    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))

    let payload = try OracleJson.parse(result.standardOutput)
    let context = try #require(
      payload.at("hookSpecificOutput.additionalContext")?.stringValue
        ?? payload["additionalContext"]?.stringValue,
    )
    // "use-cases" somewhere ahead of the absolute path of the wrapper, which is
    // what the TypeScript's regexp says.
    let absolute = "\(OracleLayout.repositoryRoot)/bin/use-cases"
    let named = context.components(separatedBy: "\n").contains { line in
      line.contains("use-cases") && line.contains(absolute)
    }
    #expect(named, Comment(rawValue: "the bootstrap must name \(absolute)"))
  }

  @Test
  func `an unwritable CLAUDE_ENV_FILE still delivers the bootstrap and names the file on stderr`()
    async throws
  {
    let directory = try TemporaryDirectory("session-path")
    let envFile = "\(directory.path)/missing-dir/env.sh"

    let result = try await Self.runHook(["CLAUDE_ENV_FILE": envFile])
    #expect(result.exitCode == 0)
    #expect(try Self.bootstrapContext(result.standardOutput).contains("<EXTREMELY_IMPORTANT>"))
    #expect(result.standardError.contains(envFile))
    #expect(!FileManager.default.fileExists(atPath: envFile))
  }

  // bad_the_old_name_is_gone — ADR 0007 decision 4 is a HARD rename, read
  // strictly by the owner: no alias AND no tombstone. The plugin ships nothing
  // under the old name, so a session that types it gets the shell's own
  // `command not found`. This test is what stops an alias being reinstated.
  @Test
  func `the plugin ships no entry point under the old name`() throws {
    #expect(!FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/bin/uc"))
    // Nothing else in bin/ answers to it either.
    let entries = try FileManager.default
      .contentsOfDirectory(atPath: "\(OracleLayout.repositoryRoot)/bin")
    #expect(!entries.contains("uc"))
  }

  @Test
  func `the old name resolves to nothing on PATH after the hook exports bin`() async throws {
    let directory = try TemporaryDirectory("session-path")
    let envFile = "\(directory.path)/env.sh"
    let written = try await Self.runHook(["CLAUDE_ENV_FILE": envFile])
    #expect(written.exitCode == 0)

    // PATH is pinned to a bare base BEFORE sourcing, so the lookup answers for
    // the plugin's own bin/ and not for whatever the developer has installed.
    // (A machine with an older plugin cache really does still have a `uc`.)
    func look(_ name: String) async throws -> CliBinary.Outcome {
      try await OracleProcess.run(
        executable: "/bin/bash",
        arguments: [
          "-c",
          "export PATH=/usr/bin:/bin; source \"\(envFile)\"; command -v \(name)",
        ],
        cwd: OracleLayout.repositoryRoot,
        environment: ["PATH": "/usr/bin:/bin"],
        inheritEnvironment: false,
      )
    }

    // `command -v` is the lookup itself: non-zero means no such command.
    let old = try await look("uc")
    #expect(old.exitCode != 0)
    #expect(old.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    // ...while the new name does resolve, from that same PATH.
    let current = try await look("use-cases")
    #expect(current.exitCode == 0, Comment(rawValue: current.standardError))
    #expect(current.standardOutput.contains("\(OracleLayout.repositoryRoot)/bin/use-cases"))
  }
}

//: @use-case:end plugin.install.uc_on_path_in_session
