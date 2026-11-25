import Foundation
import Testing
@testable import UseCasesCLI

struct CommandListTests {
  /// The lines of the first block of text under "## 2. Commands" in chapter 16.
  private func chapterLines() throws -> [String] {
    let chapter = try String(
      contentsOf: DocsFolder.url().appending(path: "design/16-cli-surface.md"),
      encoding: .utf8,
    )

    let lines = chapter.components(separatedBy: "\n")
    let heading = try #require(lines.firstIndex(of: "## 2. Commands"))
    let opening = try #require(lines[heading...].firstIndex(of: "```text"))
    let closing = try #require(lines[(opening + 1)...].firstIndex(of: "```"))

    return Array(lines[(opening + 1) ..< closing])
  }

  @Test
  func `every command line of chapter 16 section 2 is in the list`() throws {
    // A line that only carries on a description is not a command line.
    let lines = try chapterLines().filter { line in
      let text = line.trimmingCharacters(in: .whitespaces)

      return ["use-cases", "[", "--", "every command:"].contains { start in
        text.hasPrefix(start)
      }
    }

    #expect(lines.count > 20)

    for line in lines {
      let invocation = try #require(
        line.trimmingCharacters(in: .whitespaces).components(separatedBy: "  ").first,
      )

      #expect(CommandList.text.contains(invocation), "missing from the list: \(invocation)")
    }
  }

  @Test(arguments: DesignedCommand.allCases)
  func `every designed command is listed with its name`(command: DesignedCommand) {
    #expect(CommandList.text.contains("use-cases \(command.rawValue)"))
  }

  @Test
  func `the list names the steps of verify, which plain verify refuses to guess`() {
    #expect(CommandList.text.contains("use-cases verify --start | --finish | --run | --abort"))
    #expect(CommandList.text.contains("use-cases record --interactive"))
  }
}
