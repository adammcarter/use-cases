import Foundation
import Testing

/// The black-box oracle for plugin.install.claude_from_github.
///
/// The row is about what a host finds when it installs this repo, so the test
/// inspects the SHIPPED manifests and layout. No product imports — and, alone
/// among the oracle files, no product PROCESS either: it runs neither binary,
/// so it proves the same thing whichever one the suite is pointed at.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct PluginInstallClaudeTests {
  static func manifest(in directory: String = OracleLayout.repositoryRoot) throws -> OracleJson {
    try OracleJson.parse(
      String(
        contentsOfFile: "\(directory)/.claude-plugin/plugin.json",
        encoding: .utf8,
      ),
    )
  }

  /// Every path a manifest declares, as it would resolve inside the plugin.
  static func declaredPaths(_ manifest: OracleJson) -> [String] {
    var paths = (manifest["agents"]?.arrayValue ?? []).compactMap { entry in
      entry.stringValue
    }
    for server in (manifest["mcpServers"]?.objectValue ?? [:]).values {
      for argument in (server["args"]?.arrayValue ?? []).compactMap({ entry in
        entry.stringValue
      }) where argument.contains("${CLAUDE_PLUGIN_ROOT}") {
        paths.append(argument.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}/", with: "./"))
      }
    }
    return paths
  }

  static func missingPaths(
    in directory: String,
    _ manifest: OracleJson,
  ) -> [String] {
    declaredPaths(manifest).filter { declared in
      let relative = declared.hasPrefix("./") ? String(declared.dropFirst(2)) : declared
      return !FileManager.default.fileExists(atPath: "\(directory)/\(relative)")
    }
  }

  // golden_manifests_point_at_real_files. Every declared path resolves, and the
  // MCP server is addressed through ${CLAUDE_PLUGIN_ROOT} so it works wherever
  // the host clones the plugin.
  @Test
  func `every path the Claude manifest declares exists, root-relative`() throws {
    let manifest = try Self.manifest()

    #expect(manifest["agents"] != nil, "the manifest declares its agents explicitly")
    #expect(
      Self.missingPaths(in: OracleLayout.repositoryRoot, manifest).isEmpty,
      "a declared path that does not exist would break the install",
    )

    let server = try #require(manifest.at("mcpServers.use-cases"))
    #expect(server["command"]?.stringValue == "bash")
    let arguments = (server["args"]?.arrayValue ?? []).compactMap { entry in
      entry.stringValue
    }
    #expect(
      arguments.joined(separator: " ").contains("${CLAUDE_PLUGIN_ROOT}/bin/use-cases-mcp"),
      "addressed through the plugin root, not a relative path",
    )
    // The plugin's own entry point, executable in a fresh clone: the manifest
    // no longer names an interpreter and a bundle path, so what actually runs
    // is the plugin's decision and not the host's.
    #expect(
      !manifest.encoded.contains("dist/uc"),
      "no host manifest names the committed bundle",
    )
    let wrapper = "\(OracleLayout.repositoryRoot)/bin/use-cases-mcp"
    let mode = try #require(
      try (FileManager.default.attributesOfItem(atPath: wrapper)[.posixPermissions] as? NSNumber)?
        .intValue,
    )
    #expect(mode & 0o111 != 0, "the wrapper must be executable")

    // The hook is found by CONVENTION rather than declared in the manifest:
    // hooks/hooks.json is what wires SessionStart. A root Agent Plugins
    // manifest would make Copilot ignore it, which is why none ships.
    let hooks = try OracleJson.parse(
      String(contentsOfFile: "\(OracleLayout.repositoryRoot)/hooks/hooks.json", encoding: .utf8),
    )
    let command = try #require(
      hooks.at("hooks.SessionStart.0.hooks.0.command")?.stringValue,
    )
    #expect(command.contains("${CLAUDE_PLUGIN_ROOT}/hooks/session-start"))
  }

  // bad_manifest_pointing_at_a_missing_file. The guard above is only worth
  // having if it would actually catch a break, so this proves it is not vacuous.
  @Test
  func `a manifest pointing at a missing file is caught, not shipped`() throws {
    let directory = try TemporaryDirectory("claude-install")
    try directory.makeDirectory(".claude-plugin")
    try FileManager.default.copyItem(
      atPath: "\(OracleLayout.repositoryRoot)/agents",
      toPath: directory.url.appendingPathComponent("agents").path,
    )
    // The manifest also declares the MCP entry point, so the fixture needs a
    // stub for it — otherwise that path is missing too and the case stops
    // isolating the agent it is about.
    try directory.writeFile("bin/use-cases-mcp", contents: "#!/usr/bin/env bash\n")

    var fields = try #require(Self.manifest().objectValue)
    fields["agents"] = .array([.string("./agents/use-cases-updater.md")])
    let intact = OracleJson.object(fields)
    #expect(
      Self.missingPaths(in: directory.path, intact).isEmpty,
      "the fixture itself must start clean",
    )

    fields["agents"] = .array([
      .string("./agents/use-cases-updater.md"),
      .string("./agents/does-not-exist.md"),
    ])
    let broken = OracleJson.object(fields)
    #expect(
      Self.missingPaths(in: directory.path, broken) == ["./agents/does-not-exist.md"],
      "the check must name the missing file rather than pass",
    )
  }

  // golden_marketplace_offers_the_repo_root. Without this the plugin manifest
  // is never read at all.
  @Test
  func `the marketplace manifest offers this plugin from the repo root`() throws {
    let market = try OracleJson.parse(
      String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/.claude-plugin/marketplace.json",
        encoding: .utf8,
      ),
    )
    let offered = (market["plugins"]?.arrayValue ?? []).first { plugin in
      plugin["name"]?.stringValue == "use-cases"
    }
    let found = try #require(offered, "the marketplace must offer use-cases")
    #expect(found["source"]?.stringValue == ".", "the plugin IS the repo root")
  }

  // golden_skills_in_the_scanned_dir. Skills sit where Claude scans by default,
  // and each front-matter name matches its directory so the slash command is
  // /use-cases:<name>.
  @Test
  func `the canonical skills sit in skills with names matching their directories`()
    throws
  {
    let skills = try FileManager.default.contentsOfDirectory(
      atPath: "\(OracleLayout.repositoryRoot)/skills",
    )
    #expect(skills.count >= 4)

    for name in skills {
      let body = try String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/skills/\(name)/SKILL.md",
        encoding: .utf8,
      )
      let front = try #require(
        OracleText.frontmatter(of: body),
        Comment(rawValue: "\(name) must open with frontmatter"),
      )
      #expect(
        front["name"] == name,
        Comment(rawValue: "\(name): the front-matter name must match the directory"),
      )
    }
  }

  // edge_live_session is NOT asserted here. It requires installing into Claude
  // Code and starting a session — a host observation, not something a test can
  // drive. It stays a scenario the owner watches rather than one the oracle
  // claims to cover.
  //
  // `test.todo` in vitest; Swift Testing has no todo, so it is a disabled test
  // carrying the same reason — it is listed, it is skipped, and it cannot go
  // green by accident.
  @Test(.disabled("edge_live_session — a host observation; cannot be driven from a test"))
  func `edge_live_session — a host observation; cannot be driven from a test`() {
    Issue.record("unreachable: this test is disabled")
  }
}
