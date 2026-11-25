import Testing
@testable import UseCasesCore

struct WorkspacePathCompositionTests {
  @Test
  func `the root is the path dot`() {
    #expect(WorkspacePath.root.isRoot)
    #expect(WorkspacePath.root.text == ".")
  }

  @Test(
    arguments: [
      (".", "a", "a"),
      ("a", "b", "a/b"),
      ("a/b", "c.yml", "a/b/c.yml"),
      ("a", "caf\u{E9}", "a/caf\u{E9}"),
    ],
  )
  func `a name read from disk is appended below a path`(
    base: String,
    name: String,
    expected: String,
  ) throws {
    let result = try WorkspacePath(validating: base).appending(component: name)

    #expect(result.text.isExactlyEqual(to: expected))
  }

  @Test(arguments: ["", "..", ".", "a/../b", "a\\b", "a\u{0}b", "/x", "a//b"])
  func `a name no path can spell is refused`(name: String) throws {
    let base = try WorkspacePath(validating: "a")

    #expect(throws: WorkspacePathError.self) {
      try base.appending(component: name)
    }
  }

  @Test(
    arguments: [
      (".", ".", "."),
      (".", "use-cases", "use-cases"),
      ("a", ".", "a"),
      ("a", "use-cases", "a/use-cases"),
      ("a/b", "x/y", "a/b/x/y"),
    ],
  )
  func `a relative path joins below a folder, and dot adds nothing`(
    base: String,
    relative: String,
    expected: String,
  ) throws {
    let result = try WorkspacePath(validating: base).joining(WorkspacePath(validating: relative))

    #expect(result.text == expected)
  }

  @Test(
    arguments: [
      ("a/b/c", "a/b"),
      ("a/b", "a"),
      ("a", "."),
    ],
  )
  func `a path has the folder it sits in as its parent`(
    path: String,
    parent: String,
  ) throws {
    #expect(try WorkspacePath(validating: path).parent == WorkspacePath(validating: parent))
  }

  @Test
  func `the root has no parent`() {
    #expect(WorkspacePath.root.parent == nil)
  }

  @Test
  func `ancestors run from the nearest folder up to the root`() throws {
    let path = try WorkspacePath(validating: "a/b/c")

    #expect(path.ancestors.map(\.text) == ["a/b", "a", "."])
    #expect(WorkspacePath.root.ancestors.isEmpty)
  }

  @Test
  func `a path has its last segment as its name`() throws {
    #expect(try WorkspacePath(validating: "a/b.yml").name == "b.yml")
    #expect(WorkspacePath.root.name == nil)
  }

  @Test(
    arguments: [
      ("a", "a", true),
      ("a/b", "a", true),
      ("a/b/c", "a/b", true),
      ("a", ".", true),
      (".", ".", true),
      ("ab/c", "a", false),
      ("ab", "a", false),
      ("a", "a/b", false),
      (".", "a", false),
      ("b/a", "a", false),
      ("cafe\u{301}/x", "caf\u{E9}", false),
    ],
  )
  func `a path is inside a folder by whole segments and exact spelling`(
    path: String,
    folder: String,
    expected: Bool,
  ) throws {
    let inside = try WorkspacePath(validating: path)
      .isInsideOrEqual(to: WorkspacePath(validating: folder))

    #expect(inside == expected)
  }

  @Test
  func `a literal name appends without checking`() {
    #expect(WorkspacePath.root.appending(literal: "use-cases.yml").text == "use-cases.yml")
    #expect(WorkspacePath.root.appending(literal: "a").appending(literal: "b").text == "a/b")
  }
}
