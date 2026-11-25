import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceDiscovererScopesTests {
  @Test
  func `a workspace with only a root has one scope and no problems`() throws {
    let fixture = try DiscoveryFixture()

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
    #expect(discovery.scopeTree.root.parent == nil)
    #expect(discovery.scopeTree.root.useCasesDirectory.text == "use-cases")
    #expect(discovery.diagnostics.isEmpty)
    #expect(discovery.isValid)
  }

  @Test
  func `every folder with a use-cases file is a scope, at any depth`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("auth")
    try fixture.scope("packages/billing/ui")
    try fixture.scope("a/b/c/d/e")

    let discovery = try fixture.discover()

    #expect(
      discovery.scopeTree.scopes.map(\.directory.text)
        == [".", "a/b/c/d/e", "auth", "packages/billing/ui"],
    )
  }

  @Test
  func `a scope's parent is its nearest ancestor with a use-cases file`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("auth")
    try fixture.scope("auth/oauth")
    try fixture.scope("auth/oauth/deep/er")
    try fixture.scope("packages/billing")

    let tree = try fixture.discover().scopeTree

    #expect(try tree.scope(at: .at("auth"))?.parent == .root)
    #expect(try tree.scope(at: .at("auth/oauth"))?.parent == .at("auth"))
    #expect(try tree.scope(at: .at("auth/oauth/deep/er"))?.parent == .at("auth/oauth"))
    #expect(try tree.scope(at: .at("packages/billing"))?.parent == .root)
    #expect(tree.children(of: .root).map(\.directory.text) == ["auth", "packages/billing"])
  }

  @Test
  func `each scope carries its own use_cases_dir in workspace coordinates`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("auth", "use_cases_dir: specs/uc\n")
    try fixture.scope("pay")

    let tree = try fixture.discover().scopeTree

    #expect(try tree.scope(at: .at("auth"))?.useCasesDirectory.text == "auth/specs/uc")
    #expect(try tree.scope(at: .at("pay"))?.useCasesDirectory.text == "pay/use-cases")
  }

  @Test
  func `a nested workspace is never entered and is listed apart`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("vendor/lib", "root: true\n")
    try fixture.scope("vendor/lib/inner")
    try fixture.directory.write("vendor/lib/use-cases/a.yml")
    try fixture.scope("auth")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "auth"])
    #expect(discovery.nestedWorkspaces.map(\.text) == ["vendor/lib"])
    #expect(discovery.isValid)
  }

  @Test(arguments: [".git", ".hg", ".svn", ".bzr", ".jj", ".use-cases"])
  func `the default exclusions are never entered, at any depth`(folder: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("\(folder)/inside")
    try fixture.scope("packages/x/\(folder)/inside")
    try fixture.scope("\(folder)/runs/2026/a")
    try fixture.scope("kept")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "kept"])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a git file named dot git is excluded too`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("sub/.git", "gitdir: ../.git/modules/sub\n")
    try fixture.scope("sub")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "sub"])
  }

  @Test
  func `configured exclusions are never entered`() throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nexclude: generated/**, **/node_modules/**, vendor, "
        + "build/out\n",
    )
    try fixture.scope("generated/a")
    try fixture.scope("pkg/node_modules/dep")
    try fixture.scope("vendor/x")
    try fixture.scope("deep/vendor")
    try fixture.scope("build/out/z")
    try fixture.scope("build/keep")
    try fixture.scope("vendors/y")
    try fixture.scope("generated-not")

    let discovery = try fixture.discover()

    #expect(
      discovery.scopeTree.scopes.map(\.directory.text)
        == [".", "build/keep", "deep/vendor", "generated-not", "vendors/y"],
    )
  }

  @Test
  func `an exclusion that matches a folder holding a use-cases file hides that scope`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nexclude: hidden\n")
    try fixture.scope("hidden")
    try fixture.scope("shown")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "shown"])
  }

  @Test
  func `a child scope's own exclusions are not used`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pkg", "exclude: sub/**\n")
    try fixture.scope("pkg/sub/inner")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "pkg", "pkg/sub/inner"])
  }

  @Test
  func `a directory symlink is never entered, inside or outside the workspace`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("real")
    let outside = try TemporaryDirectory()
    try outside.write("elsewhere/use-cases.yml")

    try fixture.directory.symlink("linked-inside", to: "real")
    try fixture.directory.symlink("linked-outside", to: outside.location(of: "elsewhere").path)
    try fixture.directory.symlink("loop", to: ".")
    try fixture.directory.symlink("dangling", to: "nowhere")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "real"])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a folder named use-cases dot yml is not a scope`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("pkg/use-cases.yml/inner.txt")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
  }

  @Test
  func `a use-cases file spelled in another case is not a scope`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("pkg/Use-Cases.yml")
    try fixture.directory.write("pkg2/use-cases.YML")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
  }

  @Test
  func `a use-cases file that is a symlink is invalid, named and never read`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("template.yml", "invalid\n")
    try fixture.directory.symlink("pkg/use-cases.yml", to: "../template.yml")
    try fixture.directory.symlink("dangling/use-cases.yml", to: "../nowhere.yml")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
    #expect(discovery.unreadableScopes.map(\.text) == ["dangling", "pkg"])
    #expect(
      discovery.diagnosticSummaries == [
        "dangling/use-cases.yml: configuration-is-symlink",
        "pkg/use-cases.yml: configuration-is-symlink",
      ],
    )
    #expect(discovery.diagnostics.last?.message.contains("'pkg/use-cases.yml'") == true)
    #expect(!discovery.isValid)
  }

  @Test
  func `a child scope that cannot be read is reported and the search goes on below it`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("bad", "invalid\n")
    try fixture.scope("bad/good")
    try fixture.scope("other")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "bad/good", "other"])
    #expect(discovery.unreadableScopes.map(\.text) == ["bad"])
    #expect(discovery.diagnosticSummaries == ["bad/use-cases.yml: mock-invalid"])
    #expect(discovery.diagnostics.first?.position?.line == 1)
    #expect(discovery.diagnostics.first?.severity == .error)
    #expect(!discovery.isValid)
  }

  @Test
  func `a child scope that cannot be read says how to exclude it when it is not a scope`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("build/out", "invalid\n")

    let discovery = try fixture.discover()

    #expect(
      discovery.diagnostics.first?.message.hasSuffix(
        "; if this file is not a Use Cases scope (build output, test data), exclude its "
          + "folder with discovery.exclude in the root use-cases.yml",
      ) == true,
    )
  }

  @Test
  func `a scope under an unreadable parent takes the nearest readable ancestor as its parent`(
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("a", "invalid\n")
    try fixture.scope("a/b")

    let tree = try fixture.discover().scopeTree

    #expect(try tree.scope(at: .at("a/b"))?.parent == .root)
  }

  @Test
  func `the same tree and diagnostics come back however the system lists folders`() throws {
    let forward = try DiscoveryFixture()
    let backward = try DiscoveryFixture(fileSystem: ReversedListingFileSystem())

    for fixture in [forward, backward] {
      try fixture.scope("b")
      try fixture.scope("a/z")
      try fixture.scope("a/y")
      try fixture.scope("bad", "invalid\n")
      try fixture.scope("vendor/lib", "root: true\n")
      try fixture.directory.write("use-cases/z.yml")
      try fixture.directory.write("use-cases/a/b.yaml")
      try fixture.directory.write("use-cases/a/A.YML")
      try fixture.directory.write("b/use-cases/q.yml")
    }

    let discovery = try forward.discover()
    let reversed = try backward.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "a/y", "a/z", "b"])
    #expect(discovery.scopeTree.scopes.map(\.directory) == reversed.scopeTree.scopes
      .map(\.directory))
    #expect(discovery.definitionTexts == reversed.definitionTexts)
    #expect(discovery.diagnostics == reversed.diagnostics)
    #expect(discovery.nestedWorkspaces == reversed.nestedWorkspaces)
    #expect(discovery.unreadableScopes == reversed.unreadableScopes)
  }

  @Test
  func `a folder name with a backslash is skipped with a warning when it holds no scope`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("odd\\name/notes.txt")
    try fixture.scope("fine")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "fine"])
    #expect(discovery.diagnostics.count == 1)
    #expect(discovery.diagnostics.first?.severity == .warning)
    #expect(discovery.diagnostics.first?.code.text == "unspellable-name")
    #expect(discovery.isValid)
  }

  @Test(arguments: [
    "odd\\name/use-cases.yml",
    "odd\\name/deep/er/use-cases.yml",
    "x/odd\\name/a/use-cases.yml",
  ])
  func `a folder whose name cannot be spelt is invalid when a scope is inside it`(
    configuration: String,
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write(configuration)
    try fixture.scope("fine")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "fine"])
    #expect(discovery.diagnostics.count == 1)
    #expect(discovery.diagnostics.first?.severity == .error)
    #expect(discovery.diagnostics.first?.code.text == "scope-in-unspellable-folder")
    #expect(discovery.diagnostics.first?.message.contains("odd\\\\name") == true)
    #expect(!discovery.isValid)
  }

  @Test
  func `a named pipe called use-cases dot yml is not a scope and is never opened`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.makeFIFO("pkg/use-cases.yml")
    try fixture.scope("pkg/inner")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "pkg/inner"])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test(.enabled(if: getuid() != 0, "an administrator can list any folder"))
  func `a folder that cannot be listed is reported and the rest is still found`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("open")
    try fixture.directory.write("locked/inner/x.txt")
    let locked = fixture.directory.location(of: "locked")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: locked.path,
      )
    }

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "open"])
    #expect(discovery.diagnosticSummaries == ["locked: unreadable-directory"])
    #expect(!discovery.isValid)
  }

  @Test
  func `a scope folder keeps the exact spelling the file system holds`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("cafe\u{301}")

    let discovery = try fixture.discover()

    let names = discovery.scopeTree.descendants.map(\.directory.text)
    #expect(names.count == 1)
    #expect(names.first?.isExactlyEqual(to: "cafe\u{301}") == true)
  }
}
