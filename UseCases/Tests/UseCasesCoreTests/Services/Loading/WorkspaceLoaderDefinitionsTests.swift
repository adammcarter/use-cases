import Testing
@testable import UseCasesCore

struct WorkspaceLoaderDefinitionsTests {
  private func problems(
    _ text: String,
    file: String = "use-cases/ui.yml",
  ) throws -> [String] {
    let fixture = try WorkspaceFixture()
    try fixture.write(file, text)

    return fixture.problems()
  }

  @Test
  func `a value of the wrong type is invalid and says so`() throws {
    let found = try problems(YAMLSamples.file(YAMLSamples.useCase(title: "42")))

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("use-cases/ui.yml: ") == true)
    #expect(found.first?.contains("42 is not of type 'string'") == true)
  }

  @Test
  func `a field the schema does not know is invalid, naming where it is`() throws {
    let found = try problems(YAMLSamples.file(YAMLSamples.useCase(extra: "    stray: true\n")))

    #expect(found.first?.contains("('stray' was unexpected) at use_cases/0") == true)
  }

  @Test
  func `a file in the definitions folder that is not a definition is invalid`() throws {
    let found = try problems("jobs:\n  build: {}\n", file: "use-cases/ci.yml")

    #expect(found.first?.hasPrefix("use-cases/ci.yml: ") == true)
  }

  @Test
  func `YAML that is refused names the file and the line`() throws {
    let found = try problems(
      YAMLSamples.file(YAMLSamples.useCase()).replacing(
        "    title: Dark mode\n",
        with: "    title: Dark mode\n    title: Night mode\n",
      ),
    )

    #expect(found == ["use-cases/ui.yml:3: duplicate key 'title'"])
  }

  @Test
  func `unquoted text followed by a note names the line and says to quote it`() throws {
    let found = try problems(
      YAMLSamples.file(YAMLSamples.useCase()).replacing(
        "steps: [Check it.]",
        with: "steps:\n            - Check medal #4 shows",
      ),
    )

    #expect(found.count == 1)
    #expect(found.first?.contains("'Check medal' is followed by '#4 shows'") == true)
    #expect(found.first?.contains("quote the whole text") == true)
  }

  @Test
  func `a field that names code or tools is reported once, without the schema's own complaint`()
    throws
  {
    let found = try problems(YAMLSamples.file(YAMLSamples.useCase(extra: "    runner: swift\n")))

    #expect(found.count == 1)
    #expect(found.first?.contains("names code or tools") == true)
    #expect(found.first?.contains("Additional properties") == false)
  }

  @Test
  func `two scenarios with one id are invalid`() throws {
    let found = try problems(
      YAMLSamples.file(YAMLSamples.useCase()).replacing(
        "        then: [y]\n",
        with: "        then: [y]\n      - id: on-state\n        when: [z]\n"
          + "        then: [w]\n",
      ),
    )

    #expect(found.first?.contains("two scenarios with id") == true)
  }

  @Test
  func `a definition file that is not valid UTF-8 is invalid`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.directory.write("use-cases/ui.yml", bytes: [0xFF, 0xFE, 0x00])

    let found = fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("use-cases/ui.yml: ") == true)
    #expect(found.first?.contains("not valid UTF-8") == true)
  }

  @Test
  func `every file's problems are reported together, sorted by file`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/b.yml", YAMLSamples.file(YAMLSamples.useCase(title: "42")))
    try fixture.write("use-cases/a.yml", "use_cases: [\n")
    try fixture.write("use-cases/c.yml", "use_cases: 5\n")

    let found = fixture.problems()

    #expect(found.count == 3)
    #expect(found.map { problem in String(problem.prefix(15)) } == [
      "use-cases/a.yml",
      "use-cases/b.yml",
      "use-cases/c.yml",
    ])
  }

  @Test
  func `a definitions folder problem and a file problem are reported in one load`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/bad.yml", "use_cases: [\n")
    try fixture.write("use-cases/ui.YML", YAMLSamples.file(YAMLSamples.useCase()))
    try fixture.write("svc/use-cases.yml", "schema_version: 1\nsign_off: required\n")

    let found = fixture.problems()

    #expect(found.count == 3)
    #expect(found.contains { problem in problem.contains("sign_off is root-only") })
    #expect(found.contains { problem in problem.hasPrefix("use-cases/bad.yml:") })
    #expect(found.contains { problem in problem.contains("use-cases/ui.YML") })
  }

  @Test
  func `a warning does not make the workspace invalid and is kept`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/ui.yml", YAMLSamples.file(YAMLSamples.useCase()))
    try fixture.directory.makeDirectory("node\u{7}")

    let workspace = try fixture.loaded()

    #expect(workspace.warnings.map(\.code.text) == ["unspellable-name"])
  }
}
