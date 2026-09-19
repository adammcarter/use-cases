import Foundation
import Testing

/// The Swift shape of `tests/conformance/bootstrap/session-start.test.ts`.
///
/// The plugin ships a trusted session-start bootstrap and per-host delivery so
/// an installed agent receives `bootstrap/use-cases.md` at session start without
/// having to discover it by reading the repo.
///
/// Its row — `hosts.profiles.bootstrap_autoinject` — was RETIRED on 2026-09-16
/// when npm delivery was removed (`use-cases/hosts/retired.yml`, lifecycle:
/// removed), so nothing binds to it and nothing is verified against it. The file
/// is carried anyway: its subject, `hooks/session-start`, is live and shipped,
/// and these six assertions are the only ones that read the Codex shape and the
/// no-truncation rule.
struct SessionStartBootstrapTests {
  static let hookScript = "\(OracleLayout.repositoryRoot)/hooks/session-start"
  static let bootstrapMarker = "Use Cases Activation"

  /// The TypeScript passes only PATH plus the case's own variables, so the hook
  /// sees nothing of the developer's session. Carried exactly.
  static func runHook(_ environment: [String: String]) async throws -> CliBinary.Outcome {
    var resolved = environment
    resolved["PATH"] = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return try await OracleProcess.run(
      executable: "/bin/bash",
      arguments: [hookScript],
      cwd: OracleLayout.repositoryRoot,
      environment: resolved,
      inheritEnvironment: false,
    )
  }

  @Test
  func `the polyglot hook script is shipped and executable`() throws {
    #expect(FileManager.default.fileExists(atPath: Self.hookScript))
    // Keep the executable bit for direct/manual use; host commands also invoke
    // through bash so packed install paths do not depend on tar mode
    // preservation.
    #expect(try ReleaseStandIn.permissions(of: Self.hookScript) & 0o111 != 0)
  }

  @Test
  func `the Claude shape carries the bootstrap in hookSpecificOutput additionalContext`(
  ) async throws {
    let result = try await Self.runHook(["CLAUDE_PLUGIN_ROOT": OracleLayout.repositoryRoot])
    #expect(result.exitCode == 0)

    let payload = try OracleJson.parse(result.standardOutput)
    #expect(payload.at("hookSpecificOutput.hookEventName")?.stringValue == "SessionStart")
    let context = try #require(payload.at("hookSpecificOutput.additionalContext")?.stringValue)
    #expect(context.contains(Self.bootstrapMarker))
    #expect(payload["additional_context"] == nil)
    #expect(payload["additionalContext"] == nil)
  }

  @Test
  func `the Copilot shape carries the bootstrap in a top-level additionalContext`() async throws {
    let result = try await Self.runHook([
      "CLAUDE_PLUGIN_ROOT": OracleLayout.repositoryRoot,
      "COPILOT_CLI": "1",
    ])
    #expect(result.exitCode == 0)

    let payload = try OracleJson.parse(result.standardOutput)
    let context = try #require(payload["additionalContext"]?.stringValue)
    #expect(context.contains(Self.bootstrapMarker))
    #expect(payload["hookSpecificOutput"] == nil)
  }

  @Test
  func `the Codex shape, with no Copilot env, uses hookSpecificOutput additionalContext`()
    async throws
  {
    let result = try await Self.runHook(["PLUGIN_ROOT": OracleLayout.repositoryRoot])
    #expect(result.exitCode == 0)

    let payload = try OracleJson.parse(result.standardOutput)
    let context = try #require(payload.at("hookSpecificOutput.additionalContext")?.stringValue)
    #expect(context.contains(Self.bootstrapMarker))
  }

  @Test
  func `emitted bootstrap is the trusted EXTREMELY_IMPORTANT block, not arbitrary text`()
    async throws
  {
    let result = try await Self.runHook(["CLAUDE_PLUGIN_ROOT": OracleLayout.repositoryRoot])
    let payload = try OracleJson.parse(result.standardOutput)
    let context = try #require(payload.at("hookSpecificOutput.additionalContext")?.stringValue)
    #expect(context.contains("<EXTREMELY_IMPORTANT>"))

    let bootstrap = try String(
      contentsOfFile: "\(OracleLayout.repositoryRoot)/bootstrap/use-cases.md",
      encoding: .utf8,
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    // The full bootstrap tail must survive (no truncation).
    #expect(context.contains(String(bootstrap.suffix(40))))
  }

  @Test
  func `the Claude hooks json declares SessionStart wired to the script`() throws {
    let manifest = try OracleJson.parse(
      String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/hooks/hooks.json",
        encoding: .utf8,
      ),
    )
    let sessionStart = try #require(manifest.at("hooks.SessionStart")?.arrayValue)
    #expect(!sessionStart.isEmpty)
    let first = try #require(sessionStart.first)
    #expect(first["matcher"]?.stringValue?.contains("startup") == true)
    let hooks = try #require(first["hooks"]).encoded
    #expect(hooks.contains("session-start"))
    #expect(hooks.contains("bash"))
  }
}
