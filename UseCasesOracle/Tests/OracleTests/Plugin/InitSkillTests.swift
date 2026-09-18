import Foundation
import Testing

//: @use-case:plugin.init.skill_hands_off
/// The black-box oracle for plugin.init.skill_hands_off — the Swift shape of
/// `tests/skills/init-skill.test.ts`.
///
/// The subject is the shipped `skills/init/SKILL.md`: markdown an agent reads,
/// so the test reads the same bytes the host would.
struct InitSkillTests {
  static let skillPath = "\(OracleLayout.repositoryRoot)/skills/init/SKILL.md"

  static func body() throws -> String {
    try String(contentsOfFile: skillPath, encoding: .utf8)
  }

  @Test
  func `the skill runs use-cases init, reads AGENTS md back, and ends by invoking the loop skill`()
    throws
  {
    #expect(FileManager.default.fileExists(atPath: Self.skillPath))
    let body = try Self.body()
    #expect(
      body.components(separatedBy: "\n").contains("name: init"),
      "the front-matter name is what makes it /use-cases:init",
    )
    #expect(body.contains("use-cases init --repo ."))
    #expect(body.contains("AGENTS.md"))

    let lastParagraph = body
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: "\n\n")
      .last ?? ""
    #expect(lastParagraph.contains("use-case-driven-development"))
  }

  @Test
  func `an already-initialised repo skips straight to the loop`() throws {
    let body = try Self.body()
    let saysAlreadyThere = body.range(of: "already exists", options: .caseInsensitive) != nil
      || body.range(of: "blocked", options: .caseInsensitive) != nil
    #expect(saysAlreadyThere)
    let readsTheAnswer = body.contains("recorded answer")
      || body.contains("read the answer")
      || body.contains("AGENTS.md")
    #expect(readsTheAnswer)
  }
}

//: @use-case:end plugin.init.skill_hands_off
