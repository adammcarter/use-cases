import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The guides and the skills are held true (chapter 16 §16, chapter 22 §6): every command, flag
/// and file name they mention exists, and every agent tool and tool argument they name is one the
/// MCP server offers. Nothing runs; the text is only read, so printed output a page shows is not
/// checked here: it is pasted from a run of the built tool.
struct GuidesHeldTrueTests {
  /// The skills the plugin ships (`plugin/skills`).
  private func skills() throws -> [(name: String, text: String)] {
    let folder = try DocsFolder.url().deletingLastPathComponent()
      .appending(path: "plugin/skills")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

    return try names.map { name in
      try (
        name,
        String(
          contentsOf: folder.appending(path: "\(name)/SKILL.md"),
          encoding: .utf8,
        ),
      )
    }
  }

  private func hold(_ pages: [(name: String, text: String)]) async throws {
    let check = try await GuideCheck.current()
    var gaps: [String] = []

    for page in pages {
      let found = try check.findings(in: page.text)

      #expect(found.problems == [], "\(page.name)")
      gaps += found.gaps.map { gap in
        "\(page.name): \(gap)"
      }
    }

    // A command, flag or file of the design that this build does not have is a gap; a page
    // naming one fails, so it is built or the page is changed.
    for gap in gaps {
      Issue.record("\(gap)")
    }
  }

  // @use-case:docs.held-true#swift-tests.guides
  @Test
  func `every command, flag and file a bundled guide names exists`() async throws {
    let guides = try BundledGuideLoader().guides()

    #expect(guides.count == 8)

    try await hold(
      guides.map { guide in
        (guide.name, guide.text)
      },
    )
  }

  // @use-case:end docs.held-true#swift-tests.guides

  @Test
  func `the guides name commands and flags for the check to hold true`() throws {
    let text = try BundledGuideLoader().guides().map(\.text).joined(separator: "\n")

    #expect(GuideCheck.flagNames(in: text).isSuperset(of: ["--like", "--run", "--start", "--next"]))
  }

  // @use-case:docs.held-true#swift-tests.skills
  @Test
  func `the setup skill writes the AGENTS.md block of chapter 22 exactly`() throws {
    let docs = try DocsFolder.url()
    let chapter = try String(
      contentsOf: docs.appending(path: "design/22-ucdd-skill.md"),
      encoding: .utf8,
    )
    let skill = try String(
      contentsOf: docs.deletingLastPathComponent()
        .appending(path: "plugin/skills/setup/SKILL.md"),
      encoding: .utf8,
    )
    let block = /<!-- use-cases:begin v(\d+) -->\n[\s\S]*?\n<!-- use-cases:end v\1 -->/

    let designed = try #require(chapter.firstMatch(of: block))
    let shipped = try #require(skill.firstMatch(of: block))

    #expect(String(shipped.output.0) == String(designed.output.0))
  }

  // @use-case:end docs.held-true#swift-tests.skills

  // @use-case:docs.held-true#swift-tests.skills
  @Test
  func `the plugin ships its four skills, and every command, flag and file they name exists`()
    async throws
  {
    let skills = try skills()

    #expect(skills.map(\.name) == ["adopting", "setup", "showcase", "use-case-driven-development"])
    for skill in skills {
      #expect(skill.text.hasPrefix("---\nname: \(skill.name)\ndescription: "), "\(skill.name)")
    }

    try await hold(skills)
  }
  // @use-case:end docs.held-true#swift-tests.skills
}
