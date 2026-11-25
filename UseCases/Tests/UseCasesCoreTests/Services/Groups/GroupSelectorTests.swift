import Testing
@testable import UseCasesCore

struct GroupSelectorTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/login.yml",
      YAMLSamples.file(
        prefix: "login",
        YAMLSamples.useCase("success"),
        YAMLSamples.useCase("lockout"),
      ),
    )
  }

  private func load(_ groups: String) throws -> LoadedWorkspace {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups:\n" + groups)

    return try fixture.loaded()
  }

  @Test
  func `the members of a group are the full ids of its use cases`() throws {
    let workspace = try load("  login:\n    include: { prefixes: [app.login] }\n")

    #expect(
      try GroupSelector().members(ofGroup: "login", in: workspace) == [
        "app.login.lockout",
        "app.login.success",
      ],
    )
  }

  @Test
  func `a group with no members is an empty set, not an error`() throws {
    let workspace = try load(
      "  login:\n    include: { prefixes: [app.login] }\n    exclude: { prefixes: [app.login] }\n",
    )

    #expect(try GroupSelector().members(ofGroup: "login", in: workspace).isEmpty)
  }

  @Test(arguments: ["nope", "Login", "login ", ""])
  func `a name no group has is refused and names the groups there are`(name: String) throws {
    let workspace = try load("  login:\n    include: { prefixes: [app.login] }\n")

    #expect(throws: GroupSelectionError.unknown(name: name, known: ["login"])) {
      try GroupSelector().members(ofGroup: name, in: workspace)
    }
  }

  @Test
  func `the refusal says no group, and which groups there are`() {
    #expect(
      GroupSelectionError.unknown(name: "nope", known: ["a", "b"]).message
        == "no group 'nope' in use-case-groups.yml; the groups are a, b",
    )
    #expect(
      GroupSelectionError.unknown(name: "nope", known: []).message
        == "no group 'nope': this workspace defines no groups (use-case-groups.yml)",
    )
  }
}
