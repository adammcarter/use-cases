import Testing
@testable import UseCasesCore

struct WorkspaceLoaderTests {
  @Test
  func `a workspace with a root and no use cases loads with the root as its only scope`() throws {
    let fixture = try WorkspaceFixture()

    let workspace = try fixture.loaded()

    #expect(workspace.root == fixture.directory.url)
    #expect(workspace.scopes.map(\.discovered.directory.text) == ["."])
    #expect(workspace.useCases.isEmpty)
    #expect(workspace.warnings.isEmpty)
  }

  @Test
  func `a use case is loaded under its full id with its file, scope and model`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/ui.yml", YAMLSamples.file(prefix: "dark", YAMLSamples.useCase()))

    let useCase = try #require(fixture.loaded().useCases.first)

    #expect(useCase.identifier.text == "app.dark.toggle")
    #expect(useCase.file.text == "use-cases/ui.yml")
    #expect(useCase.scope.text == ".")
    #expect(useCase.definition.title == "Dark mode")
    #expect(useCase.definition.localIdentifier.text == "toggle")
  }

  @Test
  func `scope prefixes compose root first, then the file prefix, then the local id`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("billing/use-cases.yml", YAMLSamples.child(prefix: "billing"))
    try fixture.write("billing/ui/use-cases.yml", YAMLSamples.child(prefix: "ui"))
    try fixture.write(
      "billing/ui/use-cases/pay.yml",
      YAMLSamples.file(prefix: "pay", YAMLSamples.useCase("card")),
    )

    let workspace = try fixture.loaded()

    #expect(workspace.useCases.map(\.identifier.text) == ["app.billing.ui.pay.card"])
    #expect(workspace.useCases.first?.scope.text == "billing/ui")
  }

  @Test
  func `a scope without a prefix passes its parent's namespace through`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("services/use-cases.yml", "schema_version: 1\n")
    try fixture.write("services/use-cases/a.yml", YAMLSamples.file(YAMLSamples.useCase("a")))

    #expect(try fixture.loaded().useCases.map(\.identifier.text) == ["app.a"])
  }

  @Test
  func `a root without a prefix gives bare ids`() throws {
    let fixture = try WorkspaceFixture(rootConfiguration: "schema_version: 1\nroot: true\n")
    try fixture.write("use-cases/a.yml", YAMLSamples.file(YAMLSamples.useCase("a")))

    #expect(try fixture.loaded().useCases.map(\.identifier.text) == ["a"])
  }

  @Test
  func `use cases come scope by scope, files by path, and each file in the order written`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/b.yml",
      YAMLSamples.file(prefix: "b", YAMLSamples.useCase("two"), YAMLSamples.useCase("one")),
    )
    try fixture.write("use-cases/a.yml", YAMLSamples.file(prefix: "a", YAMLSamples.useCase("x")))
    try fixture.write("z/use-cases.yml", YAMLSamples.child(prefix: "z"))
    try fixture.write("z/use-cases/z.yml", YAMLSamples.file(YAMLSamples.useCase("y")))

    #expect(
      try fixture.loaded().useCases.map(\.identifier.text)
        == ["app.a.x", "app.b.two", "app.b.one", "app.z.y"],
    )
  }

  @Test
  func `a missing use_cases_dir reads as an empty one`() throws {
    let fixture = try WorkspaceFixture()

    #expect(try fixture.loaded().useCases.isEmpty)
  }

  @Test
  func `a nested workspace is never entered and may use root-only settings of its own`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write(
      "vendor/auth/use-cases.yml",
      "schema_version: 1\nroot: true\nprefix: auth\nsign_off: required\n",
    )
    try fixture.write("vendor/auth/use-cases/login.yml", "not: [valid\n")
    try fixture.write("use-cases/ui.yml", YAMLSamples.file(YAMLSamples.useCase()))

    let workspace = try fixture.loaded()

    #expect(workspace.useCases.map(\.identifier.text) == ["app.toggle"])
    #expect(workspace.scopes.map(\.discovered.directory.text) == ["."])
  }

  @Test
  func `a file that cannot be read as definitions does not hide the use cases of its neighbours`()
    throws
  {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/good.yml", YAMLSamples.file(YAMLSamples.useCase()))
    try fixture.write("use-cases/bad.yml", "use_cases: [\n")

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.hasPrefix("use-cases/bad.yml:") == true)
  }
}
