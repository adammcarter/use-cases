import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Every command that writes files you own refuses a file someone changed since it was read.
struct PlannedWriteChangedTests {
  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  private func changing(_ path: String) -> ChangingPlanWriting {
    let file = place.url.appendingPathComponent(path)

    return ChangingPlanWriting {
      let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
      try? Data((text + "# someone else's change\n").utf8).write(to: file)
    }
  }

  @Test
  func `init refuses a gitignore someone changed since it was read, and writes nothing`()
    async throws
  {
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
    try place.folder.write(".gitignore", "build/\n")

    let result = await place.run(
      ["init", "--no-input"],
      writer: changing(".gitignore"),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(".gitignore changed since it was read; run it again"))
    #expect(try place.read(".gitignore") == "build/\n# someone else's change\n")
    #expect(!FileManager.default
      .fileExists(atPath: place.url.appendingPathComponent("use-cases.yml").path))
  }

  @Test
  func `hooks refuses a hook someone changed since it was read, and leaves it`() async throws {
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
    _ = await place.run(
      ["hooks", "add", "commit"],
      hooks: place.clone(),
    )
    let hook = ".git/hooks/pre-commit"
    let before = try place.read(hook)

    let result = await place.run(
      ["hooks", "remove", "commit"],
      hooks: place.clone(),
      writer: changing(hook),
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("pre-commit changed since it was read; run it again"))
    #expect(try place.read(hook) == before + "# someone else's change\n")
  }
}
