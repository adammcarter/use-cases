import Foundation
import Testing

/// The black-box oracle for plugin.install.copilot_from_github and
/// plugin.install.codex_from_github — the Swift shape of
/// `tests/plugin/host-manifests.test.ts`.
///
/// Both rows are about what a host finds when it installs this repo, so the
/// subjects are the SHIPPED manifests and the real `hooks/session-start`.
struct HostManifestsTests {
  static func read(_ relativePath: String) throws -> OracleJson {
    try OracleJson.parse(
      String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/\(relativePath)",
        encoding: .utf8,
      ),
    )
  }

  static func claudeManifest() throws -> OracleJson {
    try read(".claude-plugin/plugin.json")
  }

  static func runHook(_ environment: [String: String]) async throws -> CliBinary.Outcome {
    var resolved = ProcessInfo.processInfo.environment
    resolved["CLAUDE_ENV_FILE"] = ""
    resolved["LLVM_PROFILE_FILE"] = "/dev/null"
    for (key, value) in environment {
      resolved[key] = value
    }
    return try await OracleProcess.run(
      executable: "/bin/bash",
      arguments: ["\(OracleLayout.repositoryRoot)/hooks/session-start"],
      cwd: OracleLayout.repositoryRoot,
      environment: resolved,
      inheritEnvironment: false,
    )
  }

  // plugin.install.copilot_from_github
  @Test
  func `no root Agent Plugins manifest ships; Copilot reads the Claude manifest and hook`() throws {
    // A root plugin.json switches Copilot into a mode that ignores
    // hooks/hooks.json, and with it the bootstrap. Observed live 2026-09-16.
    #expect(!FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/plugin.json"))
    #expect(!FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/mcp.json"))

    let claude = try Self.claudeManifest()
    #expect(claude.at("mcpServers.use-cases.command")?.stringValue == "bash")
    let arguments = (claude.at("mcpServers.use-cases.args")?.arrayValue ?? [])
      .compactMap { entry in
        entry.stringValue
      }
    #expect(arguments == ["${CLAUDE_PLUGIN_ROOT}/bin/use-cases-mcp"])
    #expect(
      FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/bin/use-cases-mcp"),
    )

    let hooks = try Self.read("hooks/hooks.json")
    let sessionStart = try #require(hooks.at("hooks.SessionStart")).encoded
    #expect(sessionStart.contains("${CLAUDE_PLUGIN_ROOT}/hooks/session-start"))
  }

  @Test
  func `the session-start hook delivers the bootstrap in Copilot's shape and in Claude's`()
    async throws
  {
    let copilot = try await Self.runHook(["COPILOT_CLI": "1"])
    #expect(copilot.exitCode == 0, Comment(rawValue: copilot.standardError))
    let copilotOut = try OracleJson.parse(copilot.standardOutput)
    #expect(copilotOut["hookSpecificOutput"] == nil)
    #expect(copilotOut["additionalContext"]?.stringValue?.contains("<EXTREMELY_IMPORTANT>") == true)

    let plain = try await Self.runHook([:])
    let plainOut = try OracleJson.parse(plain.standardOutput)
    #expect(
      plainOut.at("hookSpecificOutput.additionalContext")?.stringValue?
        .contains("<EXTREMELY_IMPORTANT>") == true,
    )
  }

  @Test(
    .disabled(
      Comment(
        rawValue: "live: copilot plugin install + copilot mcp enable — performed "
          + "2026-09-16 against the worktree; recorded as showcase evidence, not here",
      ),
    ),
  )
  func `live: copilot plugin install and mcp enable give skills, bootstrap and tools`() {
    Issue.record("unreachable: this test is disabled")
  }

  // plugin.install.codex_from_github
  @Test
  func `codex-plugin plugin json declares skills, MCP and the hook in Codex's own form`() throws {
    let claude = try Self.claudeManifest()
    let codex = try Self.read(".codex-plugin/plugin.json")
    #expect(codex["name"]?.stringValue == claude["name"]?.stringValue)
    #expect(codex["version"]?.stringValue == claude["version"]?.stringValue)
    #expect(codex["skills"]?.stringValue == "./skills/")
    #expect(codex["mcpServers"]?.stringValue == "./.codex-plugin/mcp.json")
    let sessionStart = try #require(codex.at("hooks.hooks.SessionStart")).encoded
    #expect(sessionStart.contains("${PLUGIN_ROOT}/hooks/session-start"))

    // Same resolution mechanism Codex was observed to work with — a relative
    // script under cwd "." — with the interpreter swapped for bash and the
    // bundle path for the plugin's own entry point.
    let mcp = try Self.read(".codex-plugin/mcp.json")
    let server = try #require(mcp.at("mcpServers.use-cases"))
    #expect(
      server == .object([
        "command": .string("bash"),
        "args": .array([.string("./bin/use-cases-mcp")]),
        "cwd": .string("."),
      ]),
    )
    #expect(
      FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/bin/use-cases-mcp"),
    )
    // A root .mcp.json is workspace config to Copilot and overrides the
    // plugin's server there with a path that cannot resolve. Observed live
    // 2026-09-16.
    #expect(!FileManager.default.fileExists(atPath: "\(OracleLayout.repositoryRoot)/.mcp.json"))
  }

  @Test(
    .disabled(
      Comment(
        rawValue: "live: skills listed as use-cases:<name>; MCP tools blocked by "
          + "the usage cap until 2026-09-21",
      ),
    ),
  )
  func `live: codex lists the skills and the MCP tools`() {
    Issue.record("unreachable: this test is disabled")
  }
}
