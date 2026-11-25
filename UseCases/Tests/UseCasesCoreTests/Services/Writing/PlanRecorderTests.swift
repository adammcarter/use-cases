import Foundation
import Testing
@testable import UseCasesCore

struct PlanRecorderTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
    try directory.write("a.yml", "held")
    try directory.write("b.yml", "held too")
  }

  private func recorded(_ changes: [FileChange]) -> [FileChange] {
    PlanRecorder().recording([
      FolderWrite(
        folder: directory.url,
        plan: WritePlan(changes: changes),
      ),
    ])[0].plan.changes
  }

  @Test
  func `a file to replace or delete is noted as it is now`() throws {
    let found = try recorded([
      FileChange(action: .replace, path: WorkspacePath(validating: "a.yml"), bytes: [1]),
      .delete(WorkspacePath(validating: "b.yml")),
    ])

    #expect(found.map(\.expected) == [Array("held".utf8), Array("held too".utf8)])
  }

  @Test
  func `what the planner noted is kept`() throws {
    let found = try recorded([
      FileChange(
        action: .replace,
        path: WorkspacePath(validating: "a.yml"),
        bytes: [1],
        expected: [9],
      ),
    ])

    #expect(found.map(\.expected) == [[9]])
  }

  @Test
  func `a file to create, and one that is not there, are left as they are`() throws {
    let found = try recorded([
      .create(WorkspacePath(validating: "new.yml"), text: "x"),
      .delete(WorkspacePath(validating: "gone.yml")),
    ])

    #expect(found.map(\.expected) == [nil, nil])
  }

  @Test
  func `the rest of each change is untouched`() throws {
    let before = try FileChange.delete(WorkspacePath(validating: "a.yml"))
    let after = try #require(recorded([before]).first)

    #expect(after.action == .delete)
    #expect(after.path == "a.yml")
    #expect(after.bytes == before.bytes)
  }
}
