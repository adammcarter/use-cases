import ArgumentParser
import Foundation
import Testing
@testable import UseCasesCLI

/// Chapter 19 §7: every `use-cases` command in the CI recipes is a real command with real flags.
/// Nothing runs; the command line is only read.
struct CiRecipeCommandTests {
  /// The documents that hold the recipes: chapter 19 and every recipe under `docs/ci`.
  private func recipes() throws -> [(name: String, text: String)] {
    let docs = try DocsFolder.url()
    let folder = docs.appending(path: "ci")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { name in
        name.hasSuffix(".md")
      }
      .sorted()

    var found: [(name: String, text: String)] = try [
      (
        "design/19-ci.md",
        String(contentsOf: docs.appending(path: "design/19-ci.md"), encoding: .utf8),
      ),
    ]

    for name in names {
      try found.append(
        (
          "ci/" + name,
          String(contentsOf: folder.appending(path: name), encoding: .utf8),
        ),
      )
    }

    return found
  }

  @Test
  func `the recipes hold commands to check`() throws {
    let counts = try recipes().map { recipe in
      try RecipeCommands.arguments(in: recipe.text).count
    }

    #expect(counts.count >= 3)
    #expect(counts.reduce(0, +) >= 12)
    // Chapter 19 and one recipe for each provider; the folder's README has none.
    #expect(counts.filter { $0 >= 3 }.count >= 3)
  }

  @Test
  func `every command line in the recipes is read by the real command line`() throws {
    var gaps: [String] = []

    for recipe in try recipes() {
      for arguments in try RecipeCommands.arguments(in: recipe.text) {
        let line = "\(recipe.name): `use-cases \(arguments.joined(separator: " "))`"

        // A command that is designed and not built has no flags to read yet: a known gap.
        guard DesignedCommand(rawValue: arguments[0])?.isBuilt == true else {
          gaps.append(line)
          continue
        }

        do {
          _ = try UseCasesCommand.parseAsRoot(arguments)
        } catch {
          Issue.record("\(line) is not a command line: \(UseCasesCommand.message(for: error))")
        }
      }
    }

    withKnownIssue("a recipe names a command that is not built yet", isIntermittent: true) {
      for gap in gaps {
        Issue.record("\(gap) is not built yet")
      }
    }
  }
}
