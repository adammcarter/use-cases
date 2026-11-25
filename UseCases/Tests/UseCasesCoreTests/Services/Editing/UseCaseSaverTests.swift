import Foundation
import Testing
@testable import UseCasesCore

struct UseCaseSaverTests {
  private static let behaviour = String(repeating: "ab", count: 32)

  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/dark.yml",
      YAMLSamples.file(
        prefix: "dark",
        YAMLSamples.useCase(),
        YAMLSamples.useCase(
          "signed",
          extra: """
              approved:
                by: Sam
                "on": "2026-10-11"
                behaviour: "\(Self.behaviour)"\n
          """,
        ),
      ),
    )
  }

  private func saver(sending value: AuthoredValue) -> UseCaseSaver {
    UseCaseSaver(
      reader: MockAuthoredInput(AuthoredInput(name: "stdin", value: value)),
      checker: UseCaseInputChecker(),
      placer: UseCasePlacer(),
      editor: DefinitionFileEditor(),
    )
  }

  private func sent(
    _ identifier: String,
    title: String = "Dark mode",
    extra: [AuthoredMember] = [],
  ) -> AuthoredValue {
    .object(
      [
        AuthoredMember(key: "id", value: .string(identifier)),
        AuthoredMember(key: "title", value: .string(title)),
      ] + extra,
    )
  }

  private func plan(_ value: AuthoredValue) throws -> UseCaseChange {
    try saver(sending: value).plan(
      savingFrom: "-",
      in: fixture.loaded(),
    )
  }

  private func text(of path: String) throws -> String {
    try String(
      contentsOf: fixture.directory.location(of: path),
      encoding: .utf8,
    )
  }

  private func approval(by name: String) -> AuthoredMember {
    AuthoredMember(
      key: "approved",
      value: .object([
        AuthoredMember(key: "by", value: .string(name)),
        AuthoredMember(key: "on", value: .string("2026-10-11")),
        AuthoredMember(key: "behaviour", value: .string(Self.behaviour)),
      ]),
    )
  }

  @Test
  func `a use case sent as it is already written changes nothing`() throws {
    let workspace = try fixture.loaded()
    let shown = try UseCaseShower().show(
      "app.dark.toggle",
      in: workspace,
    )
    let value = try StrictYAMLReader().read(
      shown.yamlLines.joined(separator: "\n") + "\n",
      file: "stdin",
      kind: .useCase,
    )

    let change = try saver(sending: value).plan(
      savingFrom: "-",
      in: workspace,
    )

    #expect(change.action == .unchanged)
    #expect(change.file == "use-cases/dark.yml")
    #expect(change.writes.isEmpty)
    #expect(change.warnings.isEmpty)
    #expect(change.divergence(in: workspace) == nil)
  }

  @Test
  func `a use case that is there is replaced in its own file`() throws {
    let change = try plan(sent("app.dark.toggle", title: "Dark mode, changed"))

    #expect(change.action == .replaced)
    #expect(change.file == "use-cases/dark.yml")
    #expect(change.writes.changes.map(\.action) == [.replace])
    #expect(change.writes.changes.map(\.path) == ["use-cases/dark.yml"])
  }

  @Test
  func `a new use case joins its group's file`() throws {
    let change = try plan(sent("app.dark.contrast"))

    #expect(change.action == .added)
    #expect(change.file == "use-cases/dark.yml")
    #expect(change.writes.changes.map(\.action) == [.replace])
  }

  @Test
  func `a new use case of a new group is the first of a new file`() throws {
    let change = try plan(sent("app.refunds.partial"))

    #expect(change.action == .created)
    #expect(change.file == "use-cases/refunds.yml")
    #expect(change.writes.changes.map(\.action) == [.create])
  }

  @Test
  func `nothing is written by the plan, only described`() throws {
    let before = try text(of: "use-cases/dark.yml")

    _ = try plan(sent("app.dark.toggle", title: "Changed"))

    #expect(try text(of: "use-cases/dark.yml") == before)
  }

  @Test
  func `a save without a sign-off keeps the one the use case has`() throws {
    let change = try plan(sent("app.dark.signed", title: "Signed, retitled"))
    let written = try #require(change.writes.changes.first)
    let kept = written.text

    #expect(kept.contains("title: Signed, retitled"))
    #expect(kept.contains("approved:"))
    #expect(kept.contains(Self.behaviour))
  }

  @Test
  func `a save that brings the sign-off the use case has is a save like any other`() throws {
    let change = try plan(sent("app.dark.signed", extra: [approval(by: "Sam")]))

    #expect(change.action == .replaced)
  }

  @Test(arguments: ["app.dark.signed", "app.dark.toggle", "app.dark.brandnew"])
  func `a save never writes a sign-off that is not the use case's own`(
    identifier: String,
  ) {
    #expect(throws: UseCaseEditingError.approvalNotBySave(identifier: identifier)) {
      try plan(sent(identifier, extra: [approval(by: "Someone")]))
    }
  }

  @Test
  func `a use case with no group, and one straight under a namespace, are refused`() {
    #expect(throws: UseCaseEditingError.noGroup(identifier: "orphan")) {
      try plan(sent("orphan"))
    }
    #expect(throws: UseCaseEditingError.needsGroup(identifier: "app.loose", namespace: "app")) {
      try plan(sent("app.loose"))
    }
  }

  @Test
  func `input that cannot be read is told as it was`() {
    let saver = UseCaseSaver(
      reader: MockAuthoredInput(failing: .notAFile(path: "missing.yml")),
      checker: UseCaseInputChecker(),
      placer: UseCasePlacer(),
      editor: DefinitionFileEditor(),
    )

    #expect(throws: UseCaseEditingError.input(message: "'missing.yml' is not a file")) {
      try saver.plan(
        savingFrom: "missing.yml",
        in: fixture.loaded(),
      )
    }
  }

  @Test
  func `the workspace as the change leaves it is held to what was meant`() throws {
    let change = try plan(sent("app.dark.contrast"))

    #expect(try change.divergence(in: fixture.loaded()) != nil)
  }
}
