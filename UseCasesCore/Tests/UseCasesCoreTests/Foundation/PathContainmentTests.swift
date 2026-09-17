import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Containment is the boundary that stops an attacker-controlled path becoming a
/// read or a write outside the workspace. It resolves symlinks on the existing
/// prefix, so a not-yet-created leaf under a symlinked parent is still caught.
struct PathContainmentTests {
  private let temporary: TemporaryDirectory

  init() throws {
    temporary = try TemporaryDirectory()
  }

  @Test
  func `a root contains itself`() {
    #expect(PathContainment.isContained(root: temporary.url.path, target: temporary.url.path))
  }

  @Test
  func `a root contains an existing child`() throws {
    let child = try temporary.makeDirectory("use-cases")

    #expect(PathContainment.isContained(root: temporary.url.path, target: child.path))
  }

  @Test
  func `a root contains a child that does not exist yet`() {
    let target = temporary.url.appendingPathComponent("not/created/yet.json").path

    #expect(PathContainment.isContained(root: temporary.url.path, target: target))
  }

  @Test
  func `a parent directory is not contained`() {
    let parent = temporary.url.deletingLastPathComponent().path

    #expect(!PathContainment.isContained(root: temporary.url.path, target: parent))
  }

  @Test(arguments: ["..", "../..", "../sibling", "a/../../escape"])
  func `a relative escape is refused`(suffix: String) {
    let target = temporary.url.appendingPathComponent(suffix).path

    #expect(!PathContainment.isContained(root: temporary.url.path, target: target))
  }

  @Test
  func `a symlink pointing outside the root is not contained`() throws {
    let outside = try TemporaryDirectory()
    let link = try temporary.makeSymlink("escape-hatch", to: outside.url)

    #expect(!PathContainment.isContained(root: temporary.url.path, target: link.path))
  }

  @Test
  func `a file beneath a symlinked parent that escapes is not contained`() throws {
    let outside = try TemporaryDirectory()
    try temporary.makeSymlink("escape-hatch", to: outside.url)
    let target = temporary.url.appendingPathComponent("escape-hatch/secret.json").path

    #expect(!PathContainment.isContained(root: temporary.url.path, target: target))
  }

  @Test
  func `a symlink pointing back inside the root stays contained`() throws {
    let inside = try temporary.makeDirectory("real")
    let link = try temporary.makeSymlink("alias", to: inside)

    #expect(PathContainment.isContained(root: temporary.url.path, target: link.path))
  }

  // Measured against the TypeScript on 2026-09-17: `existsSync` follows a
  // symlink, so a BROKEN one fails the existence check, realpath never runs,
  // and the lexical path — still inside the root — is reported as contained.
  // A live link to the same outside directory is refused. Surprising, and
  // frozen by ADR 0007 decision 8, so it is pinned rather than corrected.
  @Test
  func `a broken symlink pointing outside stays contained`() throws {
    let missing = temporary.url
      .deletingLastPathComponent()
      .appendingPathComponent("definitely-not-here-\(UUID().uuidString)")
    let broken = try temporary.makeSymlink("broken-link", to: missing)

    #expect(PathContainment.isContained(root: temporary.url.path, target: broken.path))
  }

  @Test
  func `a child of a broken symlink stays contained`() throws {
    let missing = temporary.url
      .deletingLastPathComponent()
      .appendingPathComponent("definitely-not-here-\(UUID().uuidString)")
    try temporary.makeSymlink("broken-link", to: missing)
    let child = temporary.url.appendingPathComponent("broken-link/child.json").path

    #expect(PathContainment.isContained(root: temporary.url.path, target: child))
  }

  @Test
  func `resolving a contained relative path returns an absolute path`() throws {
    let resolved = try PathContainment.resolveContained(
      root: temporary.url.path,
      candidate: "use-cases/capsule.yml",
    )

    #expect(resolved == temporary.url.appendingPathComponent("use-cases/capsule.yml").path)
  }

  @Test
  func `resolving a contained absolute path returns it unchanged`() throws {
    let absolute = temporary.url.appendingPathComponent("plan.json").path

    let resolved = try PathContainment.resolveContained(
      root: temporary.url.path,
      candidate: absolute,
    )

    #expect(resolved == absolute)
  }

  @Test
  func `resolving an escaping path throws a stable path escape error`() throws {
    #expect(throws: PathError.self) {
      try PathContainment.resolveContained(
        root: temporary.url.path,
        candidate: "../../etc/passwd",
      )
    }
  }

  @Test
  func `the escape error carries the caller's message`() throws {
    let thrown = #expect(throws: PathError.self) {
      try PathContainment.resolveContained(
        root: temporary.url.path,
        candidate: "../escape",
        message: "plan file escapes the workspace boundary.",
      )
    }

    #expect(thrown == .escape("plan file escapes the workspace boundary."))
  }
}
