import Testing
@testable import UseCasesCore

struct WorkspaceLoaderOrderTests {
  /// Problems that are found in this order: a scope's configuration (discovery), then a bad
  /// file of the root scope, then a duplicate that only shows once every scope is loaded. Their
  /// files sort the other way round.
  private func fixture() throws -> WorkspaceFixture {
    let fixture = try WorkspaceFixture()
    try fixture.write("zed/use-cases.yml", "schema_version: 1\nprefix: [\n")
    try fixture.write("use-cases/b.yml", "use_cases: [\n")
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "a", YAMLSamples.useCase("x")))
    try fixture.write("a/use-cases.yml", YAMLSamples.child(prefix: "a"))
    try fixture.write("a/use-cases/x.yml", YAMLSamples.file(YAMLSamples.useCase("x")))

    return fixture
  }

  @Test
  func `problems are listed by file, not in the order they were found`() throws {
    let problems = try fixture().problems()

    #expect(problems.count == 3)
    #expect(problems.map { problem in String(problem.prefix(14)) } == [
      "use-cases/a.ym",
      "use-cases/b.ym",
      "zed/use-cases.",
    ])
  }

  @Test
  func `the order is the same on every load`() throws {
    let fixture = try fixture()

    #expect(fixture.problems() == fixture.problems())
  }

  @Test
  func `problems in one file are listed by line`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/b.yml", "use_cases:\n  - id: a\n    title: A\n    title: B\n")
    try fixture.write("use-cases/a.yml", "use_cases:\n  - id: [\n")

    let problems = fixture.problems()

    #expect(problems.count == 2)
    #expect(problems.first?.hasPrefix("use-cases/a.yml:") == true)
    #expect(problems.last?.hasPrefix("use-cases/b.yml:3:") == true)
  }
}
