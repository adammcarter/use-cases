import Foundation
import Testing
@testable import UseCasesCore

struct GitignorePlannerTests {
  private let directory: TemporaryDirectory
  private let planner = GitignorePlanner(fileSystem: LocalFileSystem())

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func planned() throws -> GitignorePlanner.Plan {
    try planner.plan(for: directory.url)
  }

  private func written(_ plan: GitignorePlanner.Plan) -> String? {
    plan.change?.text
  }

  @Test
  func `a git folder gets a new gitignore with the line`() throws {
    try directory.makeDirectory(".git")

    let plan = try planned()

    #expect(plan.outcome == .added)
    #expect(plan.change?.action == .create)
    #expect(plan.change?.path == ".gitignore")
    #expect(written(plan) == ".use-cases/\n")
    #expect(plan.notes.isEmpty)
  }

  @Test
  func `a git file, as a worktree or a submodule has, counts as well`() throws {
    try directory.write(".git", "gitdir: ../elsewhere/.git/worktrees/w")

    #expect(try planned().outcome == .added)
  }

  @Test(arguments: [
    ("node_modules/", "node_modules/\n.use-cases/\n"),
    ("node_modules/\n", "node_modules/\n.use-cases/\n"),
    ("", ".use-cases/\n"),
    ("a\r\nb", "a\r\nb\n.use-cases/\n"),
    ("# .use-cases/\n", "# .use-cases/\n.use-cases/\n"),
    ("!.use-cases/\n", "!.use-cases/\n.use-cases/\n"),
    (".use-cases/x\n", ".use-cases/x\n.use-cases/\n"),
  ])
  func `the line goes on a line of its own after what is there`(
    existing: String,
    expected: String,
  ) throws {
    try directory.write(".gitignore", existing)

    let plan = try planned()

    #expect(plan.outcome == .added)
    #expect(plan.change?.action == .replace)
    #expect(written(plan) == expected)
  }

  @Test(arguments: [
    ".use-cases", ".use-cases/", "/.use-cases", "/.use-cases/",
    "a\n.use-cases/\nb\n", ".use-cases/  \n", ".use-cases/\r\n",
  ])
  func `a line that already excludes the store is recognised, and nothing is written`(
    existing: String,
  ) throws {
    try directory.write(".gitignore", existing)

    let plan = try planned()

    #expect(plan.outcome == .present)
    #expect(plan.change == nil)
    #expect(plan.notes.isEmpty)
  }

  @Test
  func `a gitignore alone, with no git folder, is enough`() throws {
    try directory.write(".gitignore", "build/\n")

    #expect(try planned().outcome == .added)
  }

  // @use-case:init.gitignore#swift-tests.no-git
  @Test
  func `no version control writes nothing and says to exclude the store`() throws {
    let plan = try planned()

    #expect(plan.outcome == .skipped)
    #expect(plan.change == nil)
    #expect(plan.notes.count == 1)
    #expect(plan.notes.first?.contains(".use-cases/") == true)
  }

  // @use-case:end init.gitignore#swift-tests.no-git

  @Test
  func `a workspace in a subfolder of a git repository is told so, naming git`() throws {
    try directory.makeDirectory(".git")
    try directory.makeDirectory("services/pay")
    let inner = try planner.plan(for: directory.location(of: "services/pay"))

    #expect(inner.outcome == .skipped)
    #expect(inner.change == nil)
    #expect(inner.notes.first?.contains("git repository at \(directory.url.path)") == true)
  }

  @Test
  func `a gitignore that is a folder is left alone and the person is told`() throws {
    try directory.makeDirectory(".gitignore")

    let plan = try planned()

    #expect(plan.outcome == .skipped)
    #expect(plan.change == nil)
    #expect(plan.notes.first?.contains("not a regular file") == true)
  }

  @Test
  func `a gitignore that is a symlink is left alone and the person is told`() throws {
    try directory.write("shared-ignore", "build/\n")
    try directory.symlink(".gitignore", to: "shared-ignore")

    let plan = try planned()

    #expect(plan.outcome == .skipped)
    #expect(plan.change == nil)
    #expect(plan.notes.count == 1)
  }
}
