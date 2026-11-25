import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct HookPlannerTests {
  private static let program = "/opt/use-cases/bin/use-cases"

  private let tree: TemporaryDirectory

  init() throws {
    tree = try TemporaryDirectory()
  }

  private func planner(isManaged: Bool = false) -> HookPlanner {
    HookPlanner(
      git: MockGitInspector(
        location: GitLocation(
          workTree: tree.url,
          hooksFolder: tree.url.appendingPathComponent(".git/hooks"),
          isManaged: isManaged,
        ),
      ),
    )
  }

  private func plan(
    _ action: HookAction? = nil,
    _ names: [HookName] = [],
    from root: String = "",
    isManaged: Bool = false,
  ) async throws -> HooksPlan {
    try await planner(isManaged: isManaged).plan(
      HooksRequest(
        root: root.isEmpty ? tree.url : tree.url.appendingPathComponent(root),
        action: action,
        names: names,
        program: Self.program,
      ),
    )
  }

  private func script(
    _ hook: HookName,
    workspace: String = ".",
    program: String = Self.program,
  ) -> String {
    HookScript(
      hook: hook,
      workspace: workspace,
    ).text(program: program)
  }

  private func states(_ plan: HooksPlan) -> [HookState] {
    plan.hooks.map(\.state)
  }

  // MARK: - Looking

  @Test
  func `a clone with no hooks lists both as absent and writes nothing`() async throws {
    let plan = try await plan()

    #expect(plan.hooks.map(\.name) == [.commit, .push])
    #expect(states(plan) == [.absent, .absent])
    #expect(plan.changed.isEmpty)
    #expect(plan.notes.isEmpty)
    #expect(!plan.needsAttention)
    #expect(plan.writes.plan.isEmpty)
    #expect(plan.hooksFolder == ".git/hooks")
    #expect(!plan.isManaged)
  }

  @Test
  func `a hook that is exactly ours is installed, whichever program added it`() async throws {
    try tree.write(".git/hooks/pre-commit", script(.commit, program: "/somewhere/else/use-cases"))

    #expect(try await states(plan()) == [.installed, .absent])
  }

  // @use-case:hooks.opt-in#swift-tests.list
  @Test(arguments: [
    "#!/bin/sh\necho mine\n",
    "",
  ])
  func `any other file is another hook, left alone when listing`(text: String) async throws {
    try tree.write(".git/hooks/pre-push", text)

    let plan = try await plan()

    #expect(states(plan) == [.absent, .other])
    #expect(plan.notes.isEmpty)
    #expect(!plan.needsAttention)
  }

  // @use-case:end hooks.opt-in#swift-tests.list

  @Test
  func `a hook that is a folder or a link is another hook`() async throws {
    try FileManager.default.createDirectory(
      at: tree.location(of: ".git/hooks/pre-commit"),
      withIntermediateDirectories: true,
    )
    try tree.write("elsewhere", "x")
    try FileManager.default.createSymbolicLink(
      at: tree.location(of: ".git/hooks/pre-push"),
      withDestinationURL: tree.location(of: "elsewhere"),
    )

    #expect(try await states(plan()) == [.other, .other])
  }

  // @use-case:hooks.opt-in#swift-tests.list
  @Test
  func `a hook manager owns every hook, and listing says so without a note`() async throws {
    try tree.write(".git/hooks/pre-commit", script(.commit))

    let plan = try await plan(isManaged: true)

    #expect(states(plan) == [.managed, .managed])
    #expect(plan.isManaged)
    #expect(plan.notes.isEmpty)
    #expect(!plan.needsAttention)
  }

  // @use-case:end hooks.opt-in#swift-tests.list

  // MARK: - Adding

  @Test
  func `adding a hook writes the script, runnable, under the folder above the hooks`()
    async throws
  {
    let plan = try await plan(.add, [.commit])

    #expect(plan.changed == [.commit])
    #expect(states(plan) == [.installed, .absent])
    #expect(plan.writes.folder.path == tree.url.path + "/.git")
    #expect(plan.writes.plan.changes.map(\.action) == [.create])
    #expect(plan.writes.plan.changes.map(\.path) == ["hooks/pre-commit"])
    #expect(plan.writes.plan.changes.map(\.isExecutable) == [true])
    #expect(plan.writes.plan.changes.map(\.text) == [script(.commit)])
    #expect(!plan.needsAttention)
  }

  @Test
  func `both hooks are added in the fixed order whatever order they were named in`() async throws {
    let plan = try await plan(.add, [.push, .commit])

    #expect(plan.changed == [.commit, .push])
    #expect(plan.writes.plan.changes.map(\.path) == ["hooks/pre-commit", "hooks/pre-push"])
    #expect(states(plan) == [.installed, .installed])
  }

  @Test
  func `adding a hook that is installed does nothing`() async throws {
    try tree.write(".git/hooks/pre-commit", script(.commit))

    let plan = try await plan(.add, [.commit])

    #expect(plan.changed.isEmpty)
    #expect(plan.writes.plan.isEmpty)
    #expect(states(plan) == [.installed, .absent])
    #expect(!plan.needsAttention)
  }

  @Test
  func `the script remembers the program that adds it`() async throws {
    let plan = try await plan(.add, [.commit])

    #expect(plan.writes.plan.changes.first?.text.contains("if [ -e \(Self.program) ]") == true)
  }

  @Test
  func `a workspace below the top is named from the top, and the hooks folder from the workspace`()
    async throws
  {
    let plan = try await plan(.add, [.commit], from: "services/pay")

    #expect(plan.hooksFolder == "../../.git/hooks")
    #expect(plan.writes.plan.changes.map(\.text) == [script(.commit, workspace: "services/pay")])
  }

  @Test
  func `a hooks folder that is not there yet is still where the hook goes`() async throws {
    #expect(!FileManager.default.fileExists(atPath: tree.location(of: ".git").path))

    let plan = try await plan(.add, [.push])

    #expect(plan.writes.plan.changes.map(\.path) == ["hooks/pre-push"])
    #expect(states(plan) == [.absent, .installed])
  }

  @Test
  func `adding over another hook leaves it alone and gives the one line to add`() async throws {
    try tree.write(".git/hooks/pre-commit", "#!/bin/sh\necho mine\n")

    let plan = try await plan(.add, [.commit, .push])

    #expect(plan.changed == [.push])
    #expect(states(plan) == [.other, .installed])
    #expect(plan.needsAttention)
    #expect(plan.notes.count == 1)
    #expect(plan.notes.first?.contains("use-cases --workspace \".\" validate --quiet") == true)
    #expect(plan.notes.first?.hasPrefix("pre-commit already has a hook") == true)
    #expect(plan.writes.plan.changes.map(\.path) == ["hooks/pre-push"])
  }

  @Test
  func `an edited hook is no longer ours to overwrite`() async throws {
    try tree.write(".git/hooks/pre-commit", script(.commit) + "echo extra\n")

    let plan = try await plan(.add, [.commit])

    #expect(plan.changed.isEmpty)
    #expect(plan.writes.plan.isEmpty)
    #expect(plan.needsAttention)
  }

  @Test
  func `adding to a hook manager writes nothing and gives the line for its configuration`()
    async throws
  {
    let plan = try await plan(.add, [.push], isManaged: true)

    #expect(plan.changed.isEmpty)
    #expect(plan.writes.plan.isEmpty)
    #expect(plan.needsAttention)
    #expect(plan.notes.count == 1)
    #expect(plan.notes.first?.contains("core.hooksPath") == true)
    #expect(plan.notes.first?.contains("pre-push") == true)
    #expect(plan.notes.first?.contains("use-cases --workspace \".\" status --gate --quiet") == true)
  }

  // MARK: - Removing

  @Test
  func `removing a hook that is ours deletes it`() async throws {
    try tree.write(".git/hooks/pre-commit", script(.commit, program: "/other/use-cases"))

    let plan = try await plan(.remove, [.commit])

    #expect(plan.changed == [.commit])
    #expect(plan.writes.plan.changes.map(\.action) == [.delete])
    #expect(plan.writes.plan.changes.map(\.path) == ["hooks/pre-commit"])
    #expect(states(plan) == [.absent, .absent])
    #expect(!plan.needsAttention)
  }

  @Test
  func `removing a hook that is not there does nothing`() async throws {
    let plan = try await plan(.remove, [.commit])

    #expect(plan.changed.isEmpty)
    #expect(plan.writes.plan.isEmpty)
    #expect(!plan.needsAttention)
  }

  @Test
  func `removing another hook leaves it alone and says so`() async throws {
    try tree.write(".git/hooks/pre-push", "#!/bin/sh\necho mine\n")

    let plan = try await plan(.remove, [.push])

    #expect(plan.changed.isEmpty)
    #expect(plan.writes.plan.isEmpty)
    #expect(states(plan) == [.absent, .other])
    #expect(plan.needsAttention)
    #expect(plan.notes.first?.hasPrefix("pre-push is not the hook Use Cases wrote") == true)
  }

  @Test
  func `removing from a hook manager writes nothing and says so`() async throws {
    let plan = try await plan(.remove, [.commit], isManaged: true)

    #expect(plan.writes.plan.isEmpty)
    #expect(plan.needsAttention)
    #expect(plan.notes.first?.contains("core.hooksPath") == true)
  }

  // MARK: - Refusals

  @Test(arguments: [
    HooksError.notAGitRepository(folder: "/x"),
    .gitUnavailable(reason: "no git"),
  ])
  func `a clone git cannot describe is passed on as it is`(error: HooksError) async {
    let planner = HookPlanner(git: MockGitInspector(failing: error))

    await #expect(throws: error) {
      try await planner.plan(
        HooksRequest(
          root: tree.url,
          action: nil,
          names: [],
          program: Self.program,
        ),
      )
    }
  }
}
