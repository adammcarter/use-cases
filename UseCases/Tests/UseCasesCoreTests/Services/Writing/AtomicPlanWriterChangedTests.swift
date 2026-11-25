import Foundation
import Testing
@testable import UseCasesCore

struct AtomicPlanWriterChangedTests {
  private let directory: TemporaryDirectory
  private let writer = AtomicPlanWriter()

  init() throws {
    directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try directory.write("a.yml", "as planned")
  }

  private func change(
    _ action: FileChangeAction,
    _ path: String = "a.yml",
    expected: String?,
  ) throws -> WritePlan {
    try WritePlan(
      changes: [
        FileChange(
          action: action,
          path: WorkspacePath(validating: path),
          bytes: Array("new".utf8),
          expected: expected.map(\.utf8).map(Array.init),
        ),
      ],
    )
  }

  private func apply(_ plan: WritePlan) throws {
    try writer.apply(
      plan,
      in: directory.url,
    )
  }

  private func text(_ path: String) throws -> String {
    try String(
      contentsOf: directory.location(of: path),
      encoding: .utf8,
    )
  }

  @Test(arguments: [FileChangeAction.replace, .delete])
  func `a file that holds what it held when planned is changed`(action: FileChangeAction) throws {
    try apply(change(action, expected: "as planned"))

    if action == .delete {
      #expect(!FileManager.default.fileExists(atPath: directory.location(of: "a.yml").path))
    } else {
      #expect(try text("a.yml") == "new")
    }
  }

  @Test(arguments: [FileChangeAction.replace, .delete])
  func `a file someone changed since it was planned is refused and keeps their change`(
    action: FileChangeAction,
  ) throws {
    let plan = try change(action, expected: "as planned")
    try directory.write("a.yml", "someone else's change")

    #expect(throws: PlanWritingError.changed(path: "a.yml")) {
      try apply(plan)
    }

    #expect(try text("a.yml") == "someone else's change")
  }

  @Test(arguments: [FileChangeAction.replace, .delete])
  func `a file someone removed since it was planned is refused as changed and stays gone`(
    action: FileChangeAction,
  ) throws {
    let plan = try change(action, expected: "as planned")
    try FileManager.default.removeItem(at: directory.location(of: "a.yml"))

    #expect(throws: PlanWritingError.changed(path: "a.yml")) {
      try apply(plan)
    }

    #expect(!FileManager.default.fileExists(atPath: directory.location(of: "a.yml").path))
  }

  @Test
  func `nothing at all is written when one of several files changed`() throws {
    try directory.write("b.yml", "b as planned")
    let plan = try WritePlan(
      changes: [
        FileChange(
          action: .replace,
          path: WorkspacePath(validating: "b.yml"),
          bytes: Array("b new".utf8),
          expected: Array("b as planned".utf8),
        ),
        FileChange(
          action: .replace,
          path: WorkspacePath(validating: "a.yml"),
          bytes: Array("a new".utf8),
          expected: Array("as planned".utf8),
        ),
        .create(
          WorkspacePath(validating: "c.yml"),
          text: "c",
        ),
      ],
    )
    try directory.write("a.yml", "changed")

    #expect(throws: PlanWritingError.changed(path: "a.yml")) {
      try apply(plan)
    }

    #expect(try text("b.yml") == "b as planned")
    #expect(!FileManager.default.fileExists(atPath: directory.location(of: "c.yml").path))
  }

  @Test
  func `a change that did not note what the file held writes over whatever it holds`() throws {
    let plan = try change(.replace, expected: nil)
    try directory.write("a.yml", "changed")

    try apply(plan)

    #expect(try text("a.yml") == "new")
  }

  @Test
  func `a file made since it was planned is not overwritten by the plan that creates it`() throws {
    let plan = try change(.create, "made.yml", expected: nil)
    try directory.write("made.yml", "someone else's file")

    #expect(throws: PlanWritingError.exists(path: "made.yml")) {
      try apply(plan)
    }

    #expect(try text("made.yml") == "someone else's file")
  }

  @Test
  func `the message says to run it again`() {
    #expect(
      PlanWritingError.changed(path: "use-cases/a.yml").message
        == "use-cases/a.yml changed since it was read; run it again",
    )
  }

  @Test
  func `a workspace is locked by a file in its results folder, made if it is absent`() throws {
    try apply(change(.replace, expected: nil))

    #expect(FileManager.default
      .fileExists(atPath: directory.location(of: ".use-cases/write.lock").path))
  }

  @Test
  func `a folder that is not a workspace yet gets no results folder`() throws {
    let bare = try TemporaryDirectory()

    try writer.apply(
      WritePlan(changes: [.create(WorkspacePath(validating: "use-cases.yml"), text: "x")]),
      in: bare.url,
    )

    #expect(!FileManager.default.fileExists(atPath: bare.location(of: ".use-cases").path))
  }

  @Test
  func `the lock is let go when the write is through, so another can take it`() throws {
    try apply(change(.replace, expected: "as planned"))
    try directory.write("a.yml", "as planned")

    try apply(change(.replace, expected: "as planned"))

    #expect(try text("a.yml") == "new")
  }
}
