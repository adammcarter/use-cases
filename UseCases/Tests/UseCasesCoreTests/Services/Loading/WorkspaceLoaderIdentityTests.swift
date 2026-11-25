import Testing
@testable import UseCasesCore

struct WorkspaceLoaderIdentityTests {
  @Test
  func `a full id defined in two files is invalid, naming both files`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "p", YAMLSamples.useCase("x")))
    try fixture.write("use-cases/b.yml", YAMLSamples.file(prefix: "p", YAMLSamples.useCase("x")))

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.hasPrefix("use-cases/b.yml: ") == true)
    #expect(problems.first?.contains("'app.p.x'") == true)
    #expect(problems.first?.contains("'use-cases/a.yml'") == true)
  }

  @Test
  func `a full id defined twice in one file is invalid`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/a.yml",
      YAMLSamples.file(YAMLSamples.useCase("x"), YAMLSamples.useCase("x")),
    )

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.contains("more than once in this file") == true)
  }

  @Test
  func `two scopes whose prefixes compose to the same full id collide`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/b.yml", YAMLSamples.file(prefix: "b", YAMLSamples.useCase("x")))
    try fixture.write("b/use-cases.yml", YAMLSamples.child(prefix: "b"))
    try fixture.write("b/use-cases/x.yml", YAMLSamples.file(YAMLSamples.useCase("x")))

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.hasPrefix("use-cases/b.yml: ") == true)
    #expect(problems.first?.contains("'b/use-cases/x.yml'") == true)
  }

  @Test
  func `the same local id under different prefixes is fine`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "a", YAMLSamples.useCase("x")))
    try fixture.write("use-cases/b.yml", YAMLSamples.file(prefix: "b", YAMLSamples.useCase("x")))

    #expect(try fixture.loaded().useCases.map(\.identifier.text) == ["app.a.x", "app.b.x"])
  }

  @Test
  func `the report names the first file by path whatever the order the scopes were found in`()
    throws
  {
    let fixture = try WorkspaceFixture(rootConfiguration: "schema_version: 1\nroot: true\n")
    try fixture.write("z/use-cases.yml", "schema_version: 1\n")
    try fixture.write("z/use-cases/x.yml", YAMLSamples.file(YAMLSamples.useCase("x")))
    try fixture.write("use-cases/x.yml", YAMLSamples.file(YAMLSamples.useCase("x")))

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.hasPrefix("z/use-cases/x.yml: ") == true)
    #expect(problems.first?.contains("'use-cases/x.yml'") == true)
  }

  @Test
  func `a scope below one that could not be read has no ids, so it cannot collide`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("pay/use-cases.yml", "schema_version: 1\nprefix: [\n")
    try fixture.write("pay/inner/use-cases.yml", YAMLSamples.child(prefix: "inner"))
    try fixture.write("pay/inner/use-cases/a.yml", YAMLSamples.file(YAMLSamples.useCase("a")))
    try fixture.write(
      "use-cases/a.yml",
      YAMLSamples.file(prefix: "inner", YAMLSamples.useCase("a")),
    )
    try fixture.write(
      "use-cases/b.yml",
      YAMLSamples.file(prefix: "inner", YAMLSamples.useCase("a")),
    )

    let problems = fixture.problems()

    // The broken scope is reported, and so is the plain duplicate; the inner scope's own
    // `app.inner.a` is not guessed at, so it adds none.
    #expect(problems.count == 2)
    #expect(problems.first?.hasPrefix("pay/use-cases.yml:") == true)
    #expect(problems.last?.hasPrefix("use-cases/b.yml: ") == true)
  }

  @Test
  func `a child scope that is not a scope says how to exclude it, the root's own file does not`()
    throws
  {
    let fixture = try WorkspaceFixture()
    try fixture.write("build/deep/use-cases.yml", "foo: bar\n")

    let child = fixture.problems()

    #expect(!child.isEmpty)
    #expect(child.allSatisfy { problem in problem.hasPrefix("build/deep/use-cases.yml: ") })
    #expect(
      child.allSatisfy { problem in
        problem.hasSuffix(
          "; if this file is not a Use Cases scope (build output, test data), exclude its "
            + "folder with discovery.exclude in the root use-cases.yml",
        )
      },
    )

    try fixture.write("use-cases.yml", "foo: bar\n")
    let root = fixture.problems()

    #expect(root.allSatisfy { problem in !problem.contains("discovery.exclude") })
  }

  @Test
  func `files below a scope that could not be read are still checked`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("pay/use-cases.yml", "schema_version: 1\nprefix: [\n")
    try fixture.write("pay/inner/use-cases.yml", YAMLSamples.child(prefix: "inner"))
    try fixture.write("pay/inner/use-cases/bad.yml", "use_cases: [\n")

    let problems = fixture.problems()

    #expect(problems.contains { problem in problem.hasPrefix("pay/inner/use-cases/bad.yml:") })
  }
}
