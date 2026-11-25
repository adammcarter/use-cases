import Testing
@testable import UseCasesCore

struct LoadedWorkspaceSummaryTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  private static let draft = "  - id: wip\n    title: Work in progress\n"

  @Test
  func `a workspace with nothing in it counts nothing`() throws {
    let summary = try fixture.loaded().summary

    #expect(summary.useCases == 0)
    #expect(summary.ready == 0)
    #expect(summary.draft == 0)
    #expect(summary.files.isEmpty)
  }

  @Test
  func `use cases are counted by whether they are fully written`() throws {
    try fixture.write(
      "use-cases/a.yml",
      YAMLSamples.file(
        prefix: "a",
        YAMLSamples.useCase("one"),
        YAMLSamples.useCase("two"),
        Self.draft,
      ),
    )

    let summary = try fixture.loaded().summary

    #expect(summary.useCases == 3)
    #expect(summary.ready == 2)
    #expect(summary.draft == 1)
  }

  @Test
  func `the files are the definition files of every scope, sorted by path`() throws {
    try fixture.write("use-cases/b.yml", YAMLSamples.file(prefix: "b", YAMLSamples.useCase("one")))
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "a", Self.draft))
    try fixture.write("services/pay/use-cases.yml", YAMLSamples.child(prefix: "pay"))
    try fixture.write(
      "services/pay/use-cases/c.yml",
      YAMLSamples.file(prefix: "c", YAMLSamples.useCase("one")),
    )

    let summary = try fixture.loaded().summary

    #expect(
      summary.files == [
        "services/pay/use-cases/c.yml",
        "use-cases/a.yml",
        "use-cases/b.yml",
      ],
    )
    #expect(summary.useCases == 3)
  }

  @Test
  func `files that are not definition files are not counted`() throws {
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "a", Self.draft))
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n")
    try fixture.write("src/code.swift", "x\n")

    #expect(try fixture.loaded().summary.files == ["use-cases/a.yml"])
  }
}
