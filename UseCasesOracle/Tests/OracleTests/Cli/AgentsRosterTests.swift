import Foundation
import Testing

/// Shared by the three agents/roster.yml suites below, which is exactly the
/// scope `agents-roster.test.ts` shares it at: module scope inside one oracle
/// file. Nothing outside this file reads it.
enum AgentsRoster {
  /// The roster as the spec states it. Hardcoded on purpose: a test that read
  /// the same constant the product reads would agree with it by construction.
  static let canonical = ["use-cases-updater", "use-cases-demo", "use-cases-demo-prep"]

  static func body(_ name: String) throws -> String {
    try String(
      contentsOfFile: "\(OracleLayout.repositoryRoot)/agents/\(name).md",
      encoding: .utf8,
    )
  }

  static func shipped() throws -> [String] {
    try FileManager.default
      .contentsOfDirectory(atPath: "\(OracleLayout.repositoryRoot)/agents")
      .filter { file in
        file.hasSuffix(".md")
      }
      .map { file in
        String(file.dropLast(3))
      }
  }

  static func manifest() throws -> OracleJson {
    try OracleJson.parse(
      String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/.claude-plugin/plugin.json",
        encoding: .utf8,
      ),
    )
  }

  /// The command surface `--help` enumerates, which is what a body's author
  /// discovers and so what a body may cite.
  static func dispatchableCommands(_ help: String) -> Set<String> {
    Set(
      OracleText.matches("(?m)^ {2}([a-z][a-z-]+(?: [a-z][a-z-]+)?)\\s{2,}", in: help)
        .compactMap { groups in
          groups[1]
        },
    )
  }

  /// The `use-cases …` citations in a body, resolved to the command they name.
  static func citedCommands(in body: String) -> [(cited: String, first: String)] {
    OracleText.matches("`use-cases\\s+([^`]+?)`", in: body).compactMap { match in
      let tokens = (match[1] ?? "")
        .trimmingCharacters(in: .whitespaces)
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
      guard let first = tokens.first else {
        return nil
      }
      let second = tokens.count > 1 ? tokens[1] : nil
      let cited = second.map { next in
        next.hasPrefix("-") ? first : "\(first) \(next)"
      } ?? first
      return (cited, first)
    }
  }
}

/// The black-box oracle for agents/roster.yml, row `shipped_with_plugin`.
///
/// These rows are about SHIPPED ARTEFACTS — the agent bodies, the Claude
/// manifest, and the command surface an agent body may cite. Nothing here
/// imports the product; it reads what ships and drives the binary, which is
/// what a host does.
///
/// One scenario step is deliberately NOT asserted here, and the gap is flagged
/// rather than papered over: golden_declared says "confirm the published
/// package files list includes agents", but package.json has no `files` key —
/// it is `private`, and npm distribution was removed in 0.7.0 when GitHub
/// became the only source. That step describes a mechanism that no longer
/// exists. Changing the row is retiring behaviour, which is the owner's call,
/// so it stays unasserted and named here until they make it.
struct AgentsRosterShippedTests {
  // golden_declared, less the retired packaging step.
  @Test
  func `the agents directory holds exactly the roster, and the manifest declares it`()
    throws
  {
    #expect(
      try AgentsRoster.shipped().sorted() == AgentsRoster.canonical.sorted(),
      "no more and no less than the roster",
    )

    let declared = try AgentsRoster.manifest()["agents"]
    #expect(declared != nil, "the manifest declares agents explicitly, by path")
    let paths = (declared?.arrayValue ?? []).compactMap { entry in
      entry.stringValue
    }
    for name in AgentsRoster.canonical {
      #expect(
        paths.contains("./agents/\(name).md"),
        Comment(rawValue: "\(name) must be declared"),
      )
    }
  }

  // bad_roster_entry_without_a_body and bad_body_shipped_without_being_declared.
  // One equality asserts both directions: a roster name with no body, and a
  // body the roster never named, each break it.
  @Test
  func `the roster and the shipped directory are held equal in both directions`()
    throws
  {
    let shipped = try AgentsRoster.shipped()

    for name in AgentsRoster.canonical {
      #expect(
        shipped.contains(name),
        Comment(rawValue: "\(name) is in the roster and must have a body"),
      )
    }
    for name in shipped {
      #expect(
        AgentsRoster.canonical.contains(name),
        Comment(rawValue: "\(name) ships but the roster does not name it"),
      )
    }

    // And the manifest is held to the same set, so a body cannot reach one host
    // while being invisible to another.
    let declared = try AgentsRoster.manifest()["agents"]?.arrayValue ?? []
    #expect(declared.count == AgentsRoster.canonical.count)
  }
}

/// The black-box oracle for agents/roster.yml, row `bodies_hold_the_line`.
struct AgentsRosterBodiesTests {
  // golden_frontmatter_matches_the_filename.
  @Test(arguments: AgentsRoster.canonical)
  func `every agent opens with frontmatter whose name matches its filename`(
    name: String,
  ) throws {
    let front = try #require(
      try OracleText.frontmatter(of: AgentsRoster.body(name)),
      "an agent body must open with YAML frontmatter",
    )
    #expect(front["name"] == name, Comment(rawValue: "\(name) frontmatter"))
  }

  // edge_description_is_specific_enough_to_route_on. A description that merely
  // restates the name tells a dispatching agent nothing about when to reach
  // for it.
  @Test(arguments: AgentsRoster.canonical)
  func `every description is a trigger, not a restatement of the name`(
    name: String,
  ) throws {
    let front = try #require(try OracleText.frontmatter(of: AgentsRoster.body(name)))
    let description = front["description"] ?? ""
    #expect(
      description.count >= 40,
      Comment(rawValue: "\(name) needs a routable description"),
    )
    #expect(description.trimmingCharacters(in: .whitespaces) != name)
  }

  // bad_cites_a_command_the_cli_does_not_ship. The allowlist is internal, but
  // its consequence is not: every `use-cases` command a body cites must be one
  // the shipped CLI actually dispatches, which --help enumerates.
  @Test
  func `every use-cases command an agent body cites is one the CLI ships`()
    async throws
  {
    let helped = try await CliBinary.resolved().run(["--help"])
    #expect(helped.exitCode == 0)
    let dispatchable = AgentsRoster.dispatchableCommands(helped.standardOutput)
    #expect(dispatchable.count > 20, "help must enumerate the command surface")

    for name in AgentsRoster.canonical {
      for citation in try AgentsRoster.citedCommands(in: AgentsRoster.body(name)) {
        #expect(
          dispatchable.contains(citation.cited) || dispatchable.contains(citation.first),
          Comment(
            rawValue: "\(name) cites `use-cases \(citation.cited)`, which the CLI does not ship",
          ),
        )
      }
    }
  }

  // bad_claims_the_users_approval. The one thing an agent must never be
  // authorised to do.
  @Test(arguments: AgentsRoster.canonical)
  func `no agent body authorises claiming approval or calling material proof`(
    name: String,
  ) throws {
    let body = try AgentsRoster.body(name)
    #expect(
      !OracleText.contains(
        "(?i)agents?\\s+may\\s+(claim|record)\\s+(user approval|user sign-off)",
        in: body,
      ),
      Comment(rawValue: "\(name) must not authorise claiming approval"),
    )
    #expect(
      !OracleText.contains(
        "(?i)generated\\s+(plan|walkthrough|capsule|runbook)\\s+is\\s+proof",
        in: body,
      ),
      Comment(rawValue: "\(name) must not call prepared material proof"),
    )
    #expect(!OracleText.contains("(?i)\\bhost\\s+support\\s+is\\s+verified\\.", in: body))
  }

  // bad_names_one_authors_private_setup. These bodies ship to everyone who
  // installs the plugin, so one author's machine is meaningless to them.
  @Test(arguments: AgentsRoster.canonical)
  func `no agent body names a private roster, a home path, or a sibling repo`(
    name: String,
  ) throws {
    #expect(
      try !OracleText.contains("agent-setup|~/\\.claude|/Users/", in: AgentsRoster.body(name)),
      Comment(rawValue: "\(name) references a private setup"),
    )
  }
}

/// The black-box oracle for agents/roster.yml, row
/// `command_allowlist_tracks_cli`.
struct AgentsRosterAllowlistTests {
  // golden_nested_command_parity and golden_flat_command_parity. The observable
  // half of the parity guarantee: the surface an agent body may cite is the
  // surface the CLI dispatches, and --help is how a body's author discovers it.
  @Test
  func `help enumerates both nested and flat commands, the citable surface`()
    async throws
  {
    let listed = try await CliBinary.resolved().run(["--help"]).standardOutput

    for flat in ["scan", "verify", "bind", "rebind", "unbind", "init", "recover", "impact"] {
      #expect(
        listed.contains(flat),
        Comment(rawValue: "flat command \(flat) must be discoverable"),
      )
    }
    for nested in ["matrix validate", "evidence record", "showcase start", "plan showcase"] {
      #expect(
        listed.contains(nested),
        Comment(rawValue: "nested command \(nested) must be discoverable"),
      )
    }
  }

  // edge_the_commands_that_exposed_the_drift. These two are the regression this
  // gate exists for: both were real and both were once rejected as unknown.
  @Test
  func `impact and showcase request-approval are both dispatchable`() async throws {
    let binary = try CliBinary.resolved()
    let listed = try await binary.run(["--help"]).standardOutput
    #expect(listed.contains("impact"))
    #expect(listed.contains("showcase request-approval"))

    // And they answer, rather than merely appearing in a list. The envelope's
    // command field is namespaced by the module that owns the command, so the
    // CLI word `impact` reports as `markers.impact`.
    let impact = try await binary.runJson(
      ["impact", "--repo", "."],
      cwd: OracleLayout.repositoryRoot,
    )
    #expect(impact.envelope.command == "markers.impact")
  }

  // bad_registry_command_missing_from_the_allowlist. The consequence an agent
  // can see: a body citing a command the CLI does not ship is caught, which is
  // what the sibling row asserts directly. Here the guard is that the help
  // surface and the doctor's view of command references agree.
  @Test
  func `doctor reports no unknown command reference in any skill or agent`()
    async throws
  {
    let doctored = try await CliBinary.resolved().runJson(
      ["doctor", "skills", "--repo", "."],
      cwd: OracleLayout.repositoryRoot,
    )
    #expect(doctored.isOk == true, "a fictional command anywhere would fail this")
    #expect(
      !doctored.envelope.diagnostics.encoded.contains("unknown_cli_command"),
      "no unknown_cli_command may be reported",
    )
  }
}
