import Testing
@testable import UseCasesCore

struct UseCaseEditSequenceTests {
  private let fixture: BatchFixture
  private let placer = UseCasePlacer()

  init() throws {
    fixture = try BatchFixture()
  }

  private func sequence() throws -> UseCaseEditSequence {
    try UseCaseEditSequence(workspace: fixture.loaded())
  }

  private func existing(_ identifier: String) throws -> LoadedUseCase {
    try #require(
      fixture.loaded().useCases.first { useCase in
        useCase.identifier.text == identifier
      },
    )
  }

  private func add(
    _ identifier: String,
    to sequence: inout UseCaseEditSequence,
  ) throws -> EditedDefinitionFile {
    let id = try UseCaseIdentifier(validating: identifier)
    let template = try existing("app.dark.toggle").definition
    let local = try #require(id.namespace.segments.last)

    return try sequence.adding(
      template.withLocalIdentifier(local.text),
      as: id,
      placed: placer.place(
        id,
        in: sequence.workspace,
      ),
    )
  }

  @Test
  func `the last use case of a file is removed by deleting the file`() throws {
    var sequence = try sequence()

    _ = try sequence.removing(existing("app.solo.only"))

    #expect(sequence.writes.changes.map(\.action) == [.delete])
    #expect(sequence.writes.changes.map(\.path) == ["use-cases/solo.yml"])
  }

  @Test
  func `emptying a file and adding to its group again replaces the file, once`() throws {
    var sequence = try sequence()

    _ = try sequence.removing(existing("app.solo.only"))
    _ = try add("app.solo.again", to: &sequence)

    let change = try #require(sequence.writes.changes.first)

    #expect(sequence.writes.changes.count == 1)
    #expect(change.action == .replace)
    #expect(change.text.hasPrefix("prefix: solo\nuse_cases:\n  - id: again\n"))
    #expect(!change.text.contains("only"))
  }

  @Test
  func `two use cases of a new group share the one file the first of them made`() throws {
    var sequence = try sequence()

    _ = try add("app.refunds.partial", to: &sequence)
    _ = try add("app.refunds.full", to: &sequence)

    let change = try #require(sequence.writes.changes.first)

    #expect(sequence.writes.changes.map(\.path) == ["use-cases/refunds.yml"])
    #expect(change.action == .create)
    #expect(change.text.contains("- id: partial"))
    #expect(change.text.contains("- id: full"))
  }

  @Test
  func `two use cases of a new group in a child scope share one file inside that scope`() throws {
    var sequence = try sequence()

    _ = try add("app.pay.refunds.partial", to: &sequence)
    _ = try add("app.pay.refunds.full", to: &sequence)

    #expect(sequence.writes.changes.map(\.path) == ["services/pay/use-cases/refunds.yml"])
    #expect(sequence.writes.changes.map(\.action) == [.create])
  }

  @Test
  func `an edit reads the file as the edits before it left it`() throws {
    var sequence = try sequence()
    let other = try existing("app.dark.other")

    _ = try sequence.removing(existing("app.dark.toggle"))
    _ = try sequence.replacing(
      other,
      with: other.definition.withTitle("Other, retitled"),
    )

    let change = try #require(sequence.writes.changes.first)

    #expect(sequence.writes.changes.count == 1)
    #expect(change.action == .replace)
    #expect(change.text.contains("title: Other, retitled"))
    #expect(!change.text.contains("id: toggle"))
  }

  @Test
  func `the workspace follows the edits without being loaded again`() throws {
    var sequence = try sequence()

    _ = try sequence.removing(existing("app.dark.toggle"))
    _ = try add("app.dark.contrast", to: &sequence)

    let identifiers = sequence.workspace.useCases.map(\.identifier.text)

    #expect(!identifiers.contains("app.dark.toggle"))
    #expect(identifiers.contains("app.dark.contrast"))
    #expect(identifiers.count == 4)
  }

  @Test
  func `a use case replaced keeps its place and takes the new definition`() throws {
    var sequence = try sequence()
    let toggle = try existing("app.dark.toggle")

    _ = try sequence.replacing(
      toggle,
      with: toggle.definition.withTitle("New"),
    )

    let held = try #require(
      sequence.workspace.useCases.first { useCase in
        useCase.identifier.text == "app.dark.toggle"
      },
    )

    #expect(held.definition.title == "New")
    #expect(held.file == toggle.file)
    #expect(held.scope == toggle.scope)
  }

  @Test
  func `the changes are sorted by path whatever order the edits were made in`() throws {
    var sequence = try sequence()

    _ = try sequence.removing(existing("app.solo.only"))
    _ = try add("app.refunds.partial", to: &sequence)
    _ = try sequence.removing(existing("app.dark.toggle"))

    #expect(sequence.writes.changes.map(\.path) == [
      "use-cases/dark.yml", "use-cases/refunds.yml", "use-cases/solo.yml",
    ])
  }

  @Test
  func `nothing is written by the edits, only described`() throws {
    var sequence = try sequence()
    let before = fixture.text(of: "use-cases/dark.yml")

    _ = try sequence.removing(existing("app.dark.toggle"))

    #expect(fixture.text(of: "use-cases/dark.yml") == before)
  }

  @Test
  func `a use case the workspace does not hold cannot be removed`() throws {
    var sequence = try sequence()
    let toggle = try existing("app.dark.toggle")

    _ = try sequence.removing(toggle)

    #expect(throws: UseCaseEditingError.unknown(identifier: "app.dark.toggle")) {
      try sequence.removing(toggle)
    }
  }
}
