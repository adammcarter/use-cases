import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The path arithmetic underneath the resolver, spelled the way Node's `path`
/// module spells it — the answers are behaviour, so they are pinned here rather
/// than only through the roots they feed.
struct WorkspacePathTests {
  @Test(arguments: [
    "/",
    "/a",
    "/a/b",
  ])
  func `a leading slash makes a path absolute`(path: String) {
    #expect(WorkspacePath.isAbsolute(path))
  }

  @Test(arguments: [
    "",
    ".",
    "a",
    "a/b",
    "../a",
  ])
  func `anything else is relative`(path: String) {
    #expect(WorkspacePath.isAbsolute(path) == false)
  }

  @Test(arguments: [
    ("/a/./b", "/a/b"),
    ("/a/b/..", "/a"),
    ("/a/b/../..", "/"),
    ("/a/b/../../..", "/"),
    ("//a//b//", "/a/b"),
    ("/", "/"),
    ("/.", "/"),
    ("a/../b", "b"),
    ("../a", "../a"),
    ("a/../../b", "../b"),
    ("", ""),
  ])
  func `normalising collapses dot and dot dot textually`(
    path: String,
    expected: String,
  ) {
    #expect(WorkspacePath.normalize(path) == expected)
  }

  @Test(arguments: [
    ("/root", "a", "/root/a"),
    ("/root", "a/b", "/root/a/b"),
    ("/root", "./a", "/root/a"),
    ("/root", "", "/root"),
    ("/root", ".", "/root"),
    ("/root", "../a", "/a"),
    ("/root", "/elsewhere", "/elsewhere"),
    ("/root", "/elsewhere/../other", "/other"),
  ])
  func `resolving makes a value absolute against a base`(
    base: String,
    value: String,
    expected: String,
  ) {
    #expect(WorkspacePath.absolute(value, relativeTo: base) == expected)
  }

  @Test(arguments: [
    ("/a/b/c", "/a/b"),
    ("/a/b", "/a"),
    ("/a", "/"),
    ("/", "/"),
  ])
  func `the parent of a path stops at the root`(
    path: String,
    expected: String,
  ) {
    #expect(WorkspacePath.dirname(path) == expected)
  }

  @Test(arguments: [
    ("/a", "/a"),
    ("/a", "/a/b"),
    ("/a", "/a/b/c"),
    ("/", "/a"),
  ])
  func `a path inside a root is contained`(
    root: String,
    child: String,
  ) {
    #expect(WorkspacePath.isContained(root: root, child: child))
  }

  @Test(arguments: [
    ("/a", "/b"),
    ("/a", "/ab"),
    ("/a/b", "/a/bc"),
    ("/a/b", "/a"),
  ])
  func `a path outside a root, or above it, is not contained`(
    root: String,
    child: String,
  ) {
    #expect(WorkspacePath.isContained(root: root, child: child) == false)
  }

  @Test
  func `an existing path resolves through its symlinks`() throws {
    let temporary = try TemporaryDirectory()
    let real = try temporary.makeDirectory("real")
    let link = try temporary.makeSymlink("link", to: real)

    #expect(WorkspacePath.realpathIfExists(link.path) == WorkspaceFixture.realPath(real.path))
  }

  @Test
  func `a path that does not exist is returned unchanged`() throws {
    let temporary = try TemporaryDirectory()
    let absent = temporary.url.appendingPathComponent("absent").path

    #expect(WorkspacePath.realpathIfExists(absent) == absent)
  }

  /// Defence in depth: a schema-valid `use_cases_dir` cannot escape its data
  /// root, so the resolver's call site is unreachable through a valid config —
  /// exactly as in the TypeScript. The rule itself is still the guard, so it is
  /// exercised directly.
  @Test
  func `a child inside its root passes the containment guard`() throws {
    try WorkspaceContextResolver.ensureContained(
      root: "/data",
      child: "/data/use-cases",
      message: "use_cases_dir escapes data_root",
    )
  }

  @Test
  func `a root is contained in itself`() throws {
    try WorkspaceContextResolver.ensureContained(
      root: "/data",
      child: "/data",
      message: "use_cases_dir escapes data_root",
    )
  }

  @Test(arguments: [
    "/elsewhere",
    "/datax",
    "/",
  ])
  func `a child outside its root is refused with a stable escape`(child: String) {
    let error = #expect(throws: PathError.self) {
      try WorkspaceContextResolver.ensureContained(
        root: "/data",
        child: child,
        message: "use_cases_dir escapes data_root",
      )
    }

    #expect(error?.code == "path.escape")
    #expect(error?.message == "use_cases_dir escapes data_root")
  }

  // MARK: - The plugin root

  @Test
  func `the plugin root is the nearest checkout carrying a plugin manifest`() throws {
    let temporary = try TemporaryDirectory()
    try temporary.writeFile(".claude-plugin/plugin.json", contents: "{}")
    let nested = try temporary.makeDirectory("a/b/c")

    #expect(WorkspaceContextResolver.findPluginRoot(startingAt: nested.path)
      == temporary.url.path)
  }

  @Test
  func `the manifest is found in the starting directory itself`() throws {
    let temporary = try TemporaryDirectory()
    try temporary.writeFile(".claude-plugin/plugin.json", contents: "{}")

    #expect(WorkspaceContextResolver.findPluginRoot(startingAt: temporary.url.path)
      == temporary.url.path)
  }

  @Test
  func `the search reaches five levels up`() throws {
    let temporary = try TemporaryDirectory()
    try temporary.writeFile(".claude-plugin/plugin.json", contents: "{}")
    let nested = try temporary.makeDirectory("a/b/c/d/e")

    #expect(WorkspaceContextResolver.findPluginRoot(startingAt: nested.path)
      == temporary.url.path)
  }

  @Test
  func `the search stops before a manifest six levels up, and falls back`() throws {
    let temporary = try TemporaryDirectory()
    try temporary.writeFile(".claude-plugin/plugin.json", contents: "{}")
    let nested = try temporary.makeDirectory("a/b/c/d/e/f")

    #expect(WorkspaceContextResolver.findPluginRoot(startingAt: nested.path)
      == temporary.url.appendingPathComponent("a/b/c").path)
  }

  @Test
  func `a tree with no manifest falls back to three levels up`() throws {
    let temporary = try TemporaryDirectory()
    let nested = try temporary.makeDirectory("a/b/c")

    #expect(WorkspaceContextResolver.findPluginRoot(startingAt: nested.path)
      == temporary.url.path)
  }
}
