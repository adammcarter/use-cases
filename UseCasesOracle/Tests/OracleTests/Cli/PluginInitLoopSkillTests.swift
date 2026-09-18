import Foundation
import Testing

/// The black-box oracle for plugin.init.loop_skill_ported.
///
/// The row is about a SHIPPED ARTEFACT — the loop skill every host reads — so
/// this inspects what ships and drives the CLI for the command surface. No
/// product imports.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct PluginInitLoopSkillTests {
  static let skill = "use-case-driven-development"

  static func skillBody() throws -> String {
    try String(
      contentsOfFile: "\(OracleLayout.repositoryRoot)/skills/\(skill)/SKILL.md",
      encoding: .utf8,
    )
  }

  // golden_present_and_canonical. Named for its directory, and in the set the
  // doctor validates — otherwise no host sees it.
  @Test
  func `the skill is named for its directory and doctor counts it as canonical`()
    async throws
  {
    let shipped = try FileManager.default.contentsOfDirectory(
      atPath: "\(OracleLayout.repositoryRoot)/skills",
    )
    #expect(shipped.contains(Self.skill))
    let fields = try #require(
      try OracleText.frontmatter(of: Self.skillBody()),
      "a skill must open with YAML frontmatter",
    )
    #expect(fields["name"] == Self.skill)

    let doctored = try await CliBinary.resolved().runJson(
      ["doctor", "skills", "--repo", "."],
      cwd: OracleLayout.repositoryRoot,
    )
    #expect(doctored.isOk == true, "the shipped skill set must be healthy")
    let count = try #require(doctored.data["skill_count"]?.intValue)
    #expect(count >= 5)
  }

  // bad_nothing_host_specific. These bodies ship to every host, so anything
  // only one machine can do makes the skill wrong everywhere else.
  @Test(arguments: [
    "talk-to-myself", "npm install", "~/\\.claude", "agent-setup", "(?i)simulator", "(?i)xcode",
  ])
  func `it carries nothing that only one machine or host can do`(forbidden: String) throws {
    let body = try Self.skillBody()
    #expect(
      !OracleText.contains(forbidden, in: body),
      Comment(rawValue: "the loop skill must not mention \(forbidden)"),
    )
  }

  // golden_covers_the_loop. The phases, the entry point, and the commands each
  // phase names — a skill that skipped one would send an agent somewhere else.
  @Test
  func `it reads AGENTS md first, routes a bare repo to init, and covers the loop`()
    throws
  {
    let body = try Self.skillBody()

    #expect(body.contains("AGENTS.md"))
    #expect(body.contains("/use-cases:init"), "a repo with no decision goes to init")
    for phase in ["UNDERSTAND", "FRAME", "BUILD", "VERIFY", "SIGN-OFF", "LAND"] {
      #expect(body.contains(phase), Comment(rawValue: "the loop must cover \(phase)"))
    }
    for command in ["bind", "verify", "scan", "recover"] {
      #expect(
        OracleText.contains("\\b\(command)\\b", in: body),
        Comment(rawValue: "the loop must name use-cases \(command)"),
      )
    }
  }

  /// Every use-cases command the skill cites must be one the CLI actually
  /// ships — the same guarantee the agent bodies are held to.
  @Test
  func `every use-cases command the skill cites is one the CLI ships`() async throws {
    let helped = try await CliBinary.resolved().run(["--help"])
    #expect(helped.exitCode == 0)
    let dispatchable = Set(
      OracleText.matches(
        "(?m)^ {2}([a-z][a-z-]+(?: [a-z][a-z-]+)?)\\s{2,}",
        in: helped.standardOutput,
      )
      .compactMap { groups in
        groups[1]
      },
    )

    for match in try OracleText.matches("`use-cases\\s+([^`]+?)`", in: Self.skillBody()) {
      let tokens = (match[1] ?? "")
        .trimmingCharacters(in: .whitespaces)
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
      let first = try #require(tokens.first)
      let second = tokens.count > 1 ? tokens[1] : nil
      let cited = second.map { next in
        next.hasPrefix("-") ? first : "\(first) \(next)"
      } ?? first
      #expect(
        dispatchable.contains(cited) || dispatchable.contains(first),
        Comment(rawValue: "the skill cites `use-cases \(cited)`, which the CLI does not ship"),
      )
    }
  }
}
