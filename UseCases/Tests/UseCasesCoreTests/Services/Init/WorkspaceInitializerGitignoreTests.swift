import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceInitializerGitignoreTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func initializer(planning gitignorePlanner: any GitignorePlanning)
    -> WorkspaceInitializer
  {
    WorkspaceInitializer(
      fileSystem: LocalFileSystem(),
      schemaLoader: BundledSchemaLoader(),
      yamlReader: StrictYAMLReader(),
      scopeReader: ScopeConfigurationReader(),
      gitignorePlanner: gitignorePlanner,
    )
  }

  @Test
  func `the planner it was given decides the gitignore line, the outcome and the notes`()
    async throws
  {
    let line = try FileChange(
      action: .create,
      path: WorkspacePath(validating: ".gitignore"),
      bytes: Array("planned elsewhere\n".utf8),
    )
    let planner = StubGitignorePlanning(
      answering: GitignorePlanner.Plan(
        outcome: .added,
        change: line,
        notes: ["a note of the stub's"],
      ),
    )

    let plan = try initializer(planning: planner).plan(
      InitRequest(
        folder: directory.url,
        form: .minimal,
        prefix: nil,
      ),
    )

    #expect(plan.writes.changes.map(\.path) == ["use-cases.yml", ".gitignore"])
    #expect(plan.writes.changes.last == line)
    #expect(plan.gitignore == .added)
    #expect(plan.notes == ["a note of the stub's"])
    #expect(await planner.asked() == [plan.root])
  }
}
