import Testing
@testable import UseCasesCore

struct NetFileChangesTests {
  private func record(_ changes: [PlannedChange]) throws -> NetFileChanges {
    var recorded = NetFileChanges()

    for change in try WritePlan.making(changes).changes {
      recorded.record(change)
    }

    return recorded
  }

  private func net(of changes: [PlannedChange]) throws -> [PlannedChange] {
    try record(changes).net.changes.map { change in
      PlannedChange(
        action: change.action,
        path: change.path,
        text: change.text,
      )
    }
  }

  @Test
  func `a file made and then added to is made once, with the last bytes`() throws {
    let result = try net(of: [.create("a.yml", "one"), .replace("a.yml", "two")])

    #expect(result.map(\.action) == [.create])
    #expect(result.map(\.text) == ["two"])
  }

  @Test
  func `a file made and then taken away is not written at all`() throws {
    #expect(try net(of: [.create("a.yml", "one"), .delete("a.yml")]).isEmpty)
  }

  @Test
  func `a file replaced twice is replaced once`() throws {
    let result = try net(of: [.replace("a.yml", "one"), .replace("a.yml", "two")])

    #expect(result.map(\.action) == [.replace])
    #expect(result.map(\.text) == ["two"])
  }

  @Test
  func `a file replaced and then taken away is deleted`() throws {
    let result = try net(of: [.replace("a.yml", "one"), .delete("a.yml")])

    #expect(result.map(\.action) == [.delete])
  }

  @Test
  func `a file emptied and then filled again is replaced, never made over itself`() throws {
    let result = try net(of: [.delete("a.yml"), .create("a.yml", "again")])

    #expect(result.map(\.action) == [.replace])
    #expect(result.map(\.text) == ["again"])
  }

  @Test
  func `a file taken away, made again and taken away is deleted`() throws {
    let result = try net(of: [.delete("a.yml"), .create("a.yml", "x"), .delete("a.yml")])

    #expect(result.map(\.action) == [.delete])
  }

  @Test
  func `the net changes are sorted by path whatever order they were made in`() throws {
    let result = try net(of: [
      .replace("use-cases/b.yml", "b"),
      .create("use-cases/a.yml", "a"),
      .delete("use-cases/c.yml"),
    ])

    #expect(result.map(\.path) == ["use-cases/a.yml", "use-cases/b.yml", "use-cases/c.yml"])
  }

  @Test
  func `the files as they stand are the last change of each, a deletion included`() throws {
    let standing = try record([
      .replace("a.yml", "one"),
      .replace("a.yml", "two"),
      .delete("b.yml"),
    ]).standing.changes.sorted { lhs, rhs in
      lhs.path < rhs.path
    }

    #expect(standing.map(\.action) == [.replace, .delete])
    #expect(standing.map(\.text) == ["two", ""])
  }

  @Test
  func `nothing recorded is nothing to write`() {
    #expect(NetFileChanges().net.isEmpty)
    #expect(NetFileChanges().standing.isEmpty)
  }

  // MARK: - Held to the file as it was read

  private func change(
    _ action: FileChangeAction,
    _ text: String = "",
    expected: String? = nil,
  ) throws -> FileChange {
    var held: [UInt8]?

    if let expected {
      held = Array(expected.utf8)
    }

    return try FileChange(
      action: action,
      path: WorkspacePath(validating: "a.yml"),
      bytes: Array(text.utf8),
      expected: held,
    )
  }

  private func expected(after changes: [FileChange]) -> [UInt8]? {
    var recorded = NetFileChanges()

    for change in changes {
      recorded.record(change)
    }

    return recorded.net.changes.first?.expected
  }

  @Test
  func `a replaced file is held to what it held when it was first read`() throws {
    let held = try expected(
      after: [
        change(.replace, "one", expected: "on disk"),
        change(.replace, "two", expected: "one"),
      ],
    )

    #expect(held == Array("on disk".utf8))
  }

  @Test
  func `a file taken away is held to what it held when it was first read`() throws {
    let held = try expected(
      after: [
        change(.replace, "one", expected: "on disk"),
        change(.delete, expected: "one"),
      ],
    )

    #expect(held == Array("on disk".utf8))
  }

  @Test
  func `a file emptied and filled again is held to what it held before it was emptied`() throws {
    let held = try expected(
      after: [
        change(.delete, expected: "on disk"),
        change(.create, "again"),
      ],
    )

    #expect(held == Array("on disk".utf8))
  }

  @Test
  func `a file made by the edits is held to nothing, there being nothing to read`() throws {
    let held = try expected(
      after: [
        change(.create, "one"),
        change(.replace, "two", expected: "one"),
      ],
    )

    #expect(held == nil)
  }

  @Test
  func `a change that did not read the file holds it to nothing`() throws {
    #expect(try expected(after: [change(.replace, "one")]) == nil)
  }
}
