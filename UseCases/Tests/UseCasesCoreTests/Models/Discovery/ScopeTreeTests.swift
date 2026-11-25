import Testing
@testable import UseCasesCore

struct ScopeTreeTests {
  private func scope(
    _ directory: String,
    parent: String?,
  ) throws -> DiscoveredScope {
    let parentPath = try parent.map { text in
      try WorkspacePath(validating: text)
    }

    return try DiscoveredScope(
      directory: WorkspacePath(validating: directory),
      parent: parentPath,
      useCasesDirectory: WorkspacePath(validating: directory).appending(literal: "use-cases"),
      definitionFiles: [],
    )
  }

  private func makeTree() throws -> ScopeTree {
    try ScopeTree(
      root: scope(".", parent: nil),
      descendants: [
        scope("b", parent: "."),
        scope("-first", parent: "."),
        scope("b/inner", parent: "b"),
        scope("a", parent: "."),
      ],
    )
  }

  @Test
  func `the root comes first however the folders sort`() throws {
    let tree = try makeTree()

    #expect(tree.scopes.map(\.directory.text) == [".", "-first", "a", "b", "b/inner"])
    #expect(tree.root.isRoot)
  }

  @Test
  func `descendants sort by path bytes`() throws {
    let tree = try ScopeTree(
      root: scope(".", parent: nil),
      descendants: [scope("B", parent: "."), scope("a", parent: "."), scope("\u{E9}", parent: ".")],
    )

    #expect(tree.descendants.map(\.directory.text) == ["B", "a", "\u{E9}"])
  }

  @Test
  func `a scope is found by its folder`() throws {
    let tree = try makeTree()

    #expect(try tree.scope(at: WorkspacePath(validating: "b/inner"))?.parent?.text == "b")
    #expect(try tree.scope(at: WorkspacePath(validating: "nope")) == nil)
    #expect(tree.scope(at: .root)?.isRoot == true)
  }

  @Test
  func `children are the scopes whose parent is the folder`() throws {
    let tree = try makeTree()

    #expect(tree.children(of: .root).map(\.directory.text) == ["-first", "a", "b"])
    #expect(try tree.children(of: WorkspacePath(validating: "b"))
      .map(\.directory.text) == ["b/inner"])
    #expect(try tree.children(of: WorkspacePath(validating: "a")).isEmpty)
  }

  @Test
  func `a scope's configuration is its use-cases file`() throws {
    #expect(try scope(".", parent: nil).configuration.text == "use-cases.yml")
    #expect(try scope("a/b", parent: "a").configuration.text == "a/b/use-cases.yml")
  }
}
