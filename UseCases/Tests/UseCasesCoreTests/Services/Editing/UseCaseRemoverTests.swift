import Testing
@testable import UseCasesCore

struct UseCaseRemoverTests {
  private let remover = UseCaseRemover()
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/dark.yml",
      YAMLSamples.file(prefix: "dark", YAMLSamples.useCase(), YAMLSamples.useCase("other")),
    )
    try fixture.write(
      "use-cases/solo.yml",
      YAMLSamples.file(prefix: "solo", YAMLSamples.useCase("only")),
    )
  }

  private func plan(
    _ identifier: String,
    links: [ResolvedLink] = [],
  ) throws -> UseCaseChange {
    try remover.plan(
      removing: identifier,
      in: fixture.loaded(),
      links: links,
    )
  }

  @Test
  func `one of several is taken out of its file, which is replaced`() throws {
    let change = try plan("app.dark.toggle")

    #expect(change.action == .removed)
    #expect(change.file == "use-cases/dark.yml")
    #expect(change.writes.changes.map(\.action) == [.replace])
  }

  @Test
  func `the last use case of a file takes the file with it`() throws {
    let change = try plan("app.solo.only")

    #expect(change.file == "use-cases/solo.yml")
    #expect(change.writes.changes.map(\.action) == [.delete])
  }

  @Test(arguments: ["app.dark", "app.dark.nope", "toggle", ""])
  func `only a full id of a use case that is there is taken out`(identifier: String) {
    #expect(throws: UseCaseEditingError.unknown(identifier: identifier)) {
      try plan(identifier)
    }
  }

  @Test
  func `the markers that still name the use case are listed by file and place, once each`() throws {
    let links = try [
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        file: "tests/b.py",
        lines: 9 ... 11,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        file: "tests/a.py",
        lines: 16 ... 18,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        file: "tests/a.py",
        lines: 2 ... 2,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.toggle",
        route: "manual",
        binding: "again",
        file: "tests/a.py",
        lines: 16 ... 18,
      ),
      ResolvedLink.sample(
        source: .manual,
        useCase: "app.dark.toggle",
        file: "src/x.py",
        lines: 1 ... 5,
      ),
      ResolvedLink.sample(
        source: .marker,
        useCase: "app.dark.other",
        file: "tests/c.py",
        lines: 1 ... 3,
      ),
    ]

    #expect(try plan("app.dark.toggle", links: links).warnings == [
      "tests/a.py:2 is still marked for app.dark.toggle",
      "tests/a.py:16-18 is still marked for app.dark.toggle",
      "tests/b.py:9-11 is still marked for app.dark.toggle",
    ])
  }

  @Test
  func `the change expects the use case to be gone`() throws {
    let change = try plan("app.dark.toggle")

    #expect(try change.divergence(in: fixture.loaded()) != nil)
  }
}
