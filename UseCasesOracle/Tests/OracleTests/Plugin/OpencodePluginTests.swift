import Foundation
import Testing

//: @use-case:plugin.install.opencode_from_git
/// The black-box oracle for plugin.install.opencode_from_git — the Swift shape
/// of `tests/plugin/opencode-plugin.test.ts`.
///
/// The subject is `opencode/plugin.js`: JavaScript that a JavaScript host
/// executes. There is no way to prove what `setup` REGISTERS without running it,
/// so this file spawns `node` over a probe that fakes the OpenCode v2 plugin
/// context and prints what was registered as JSON. That makes `node` the one
/// external tool the Swift oracle needs — worth saying out loud, because it
/// arrives as the repository is removing Node for everything else. It is
/// resolved on PATH and a missing one FAILS, exactly as an unrunnable `UC_BIN`
/// does; a silent skip would let the row go green having run nothing.
struct OpencodePluginTests {
  static let modulePath = "\(OracleLayout.repositoryRoot)/opencode/plugin.js"

  /// A fake of the OpenCode v2 plugin context: editors for MCP and skills,
  /// session hooks by kind, and the shell `create.before` hook — enough to see
  /// what `setup` registers without booting OpenCode.
  static let probe = #"""
  const [, , modulePath, root, repoRoot] = process.argv;
  const captured = { mcp: {}, skills: [], system: {}, env: { PATH: "/usr/bin" } };
  const sessionHooks = {};
  let shellHook;
  const ctx = {
    mcp: {
      transform: async (fn) =>
        fn({
          set: (name, config) => {
            captured.mcp[name] = config;
          }
        })
    },
    skill: {
      transform: async (fn) =>
        fn({
          add: (skill) => {
            captured.skills.push(skill);
          }
        })
    },
    session: {
      hook: async (name, fn) => {
        sessionHooks[name] = fn;
      }
    },
    shell: {
      hook: async (_name, fn) => {
        shellHook = fn;
      }
    }
  };
  const mod = await import(modulePath);
  captured.defaultIdType = typeof mod.default.id;
  const definition = root === repoRoot ? mod.default : mod.definePlugin(root);
  await definition.setup(ctx);
  for (const [kind, fn] of Object.entries(sessionHooks)) {
    const event = { system: [] };
    await fn(event);
    captured.system[kind] = event.system.map((part) => part.text);
  }
  if (shellHook) {
    await shellHook({ env: captured.env });
  }
  process.stdout.write(JSON.stringify(captured));
  """#

  static func node() throws -> String {
    let search = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
    guard let found = search.lazy.map({ directory in
      "\(directory)/node"
    }).first(where: { candidate in
      FileManager.default.isExecutableFile(atPath: candidate)
    }) else {
      throw OracleFailure.binaryMissing(
        name: "node",
        searched: search,
        variable: "PATH",
      )
    }
    return found
  }

  /// Run `setup` against a plugin root and read back what it registered.
  static func runSetup(root: String) async throws -> OracleJson {
    let directory = try TemporaryDirectory("opencode-probe")
    let script = try directory.writeFile("probe.mjs", contents: probe)

    let outcome = try await OracleProcess.run(
      executable: node(),
      arguments: [
        script.path,
        URL(fileURLWithPath: modulePath).absoluteString,
        root,
        OracleLayout.repositoryRoot,
      ],
      cwd: OracleLayout.repositoryRoot,
      environment: [:],
    )
    guard outcome.exitCode == 0 else {
      throw OracleFailure.unparseableStdout(
        arguments: ["opencode/plugin.js setup"],
        exitCode: outcome.exitCode,
        standardOutput: outcome.standardOutput,
        standardError: outcome.standardError,
      )
    }
    return try OracleJson.parse(outcome.standardOutput)
  }

  @Test
  func `package json exports the plugin module and it is plain JavaScript`() throws {
    let manifest = try OracleJson.parse(
      String(contentsOfFile: "\(OracleLayout.repositoryRoot)/package.json", encoding: .utf8),
    )
    #expect(manifest["exports"]?["."]?.stringValue == "./opencode/plugin.js")
    #expect(manifest["type"]?.stringValue == "module")
    #expect(FileManager.default.fileExists(atPath: Self.modulePath))

    let source = try String(contentsOfFile: Self.modulePath, encoding: .utf8)
    for line in source.components(separatedBy: "\n") where line.hasPrefix("import ") {
      #expect(line.contains("from \"node:"), Comment(rawValue: line))
    }
  }

  @Test
  func `setup registers the MCP server, every skill, the bootstrap and use-cases on PATH`()
    async throws
  {
    let captured = try await Self.runSetup(root: OracleLayout.repositoryRoot)
    #expect(captured["defaultIdType"]?.stringValue == "string")

    let server = try #require(captured.at("mcp.use-cases"))
    #expect(
      server == .object([
        "type": .string("local"),
        "command": .array([
          .string("bash"),
          .string("\(OracleLayout.repositoryRoot)/bin/use-cases-mcp"),
        ]),
        "cwd": .string(OracleLayout.repositoryRoot),
        "enabled": .bool(true),
      ]),
    )
    let source = try String(contentsOfFile: Self.modulePath, encoding: .utf8)
    #expect(!source.contains("dist/uc"), "the module must not name the committed bundle")

    let skillDirectories = try FileManager.default
      .contentsOfDirectory(atPath: "\(OracleLayout.repositoryRoot)/skills")
      .sorted()
    let skills = try #require(captured["skills"]?.arrayValue)
    #expect(skills.compactMap { skill in
      skill["name"]?.stringValue
    }.sorted() == skillDirectories)

    for skill in skills {
      let name = try #require(skill["name"]?.stringValue)
      #expect(skill["id"]?.stringValue == name)
      #expect((skill["description"]?.stringValue ?? "").count > 10)
      // Bound to a `let` first: `#expect(!(a?.b ?? c).d)` expands into a check
      // on the OPTIONAL and reports a false failure (row 10a's note).
      let content = skill["content"]?.stringValue ?? ""
      #expect(!content.hasPrefix("---"))
      #expect(skill["location"]?.stringValue?.contains("/skills/\(name)/SKILL.md") == true)
    }

    for kind in ["context", "compaction", "generate", "title"] {
      let parts = try #require(captured["system"]?[kind]?.arrayValue)
      let injected = parts.compactMap { part in
        part.stringValue
      }.joined(separator: "\n")
      #expect(injected.contains("<EXTREMELY_IMPORTANT>"), Comment(rawValue: kind))
    }

    let path = try #require(captured.at("env.PATH")?.stringValue)
    #expect(path.components(separatedBy: ":").first == "\(OracleLayout.repositoryRoot)/bin")
  }

  @Test
  func `a missing bootstrap still registers everything and says so in the injected text`()
    async throws
  {
    // The TypeScript points this at `tests/fixtures/workspaces/minimal-valid`,
    // a tree row 10d deletes. Any directory with no `bootstrap/use-cases.md`
    // proves the same thing, so it is an empty temporary one here.
    let elsewhere = try TemporaryDirectory("opencode-root")
    let captured = try await Self.runSetup(root: elsewhere.path)
    #expect(captured.at("mcp.use-cases") != nil)
    let path = try #require(captured.at("env.PATH")?.stringValue)
    #expect(path.components(separatedBy: ":").first?.hasSuffix("/bin") == true)
    let context = try #require(captured["system"]?["context"]?.arrayValue)
      .compactMap { part in
        part.stringValue
      }.joined(separator: "\n")
    #expect(context.contains("could not be read"))
  }

  @Test(
    .disabled(
      Comment(
        rawValue: "live: opencode run shows use-cases from the plugin bin, the "
          + "use-cases tools and the bootstrap",
      ),
    ),
  )
  func `live: opencode run shows the plugin's command, tools and bootstrap`() {
    Issue.record("unreachable: this test is disabled")
  }
}

//: @use-case:end plugin.install.opencode_from_git
