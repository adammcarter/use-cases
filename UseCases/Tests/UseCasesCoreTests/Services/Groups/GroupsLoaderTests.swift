import Foundation
import Testing
@testable import UseCasesCore

struct GroupsLoaderTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try writeUseCases("login", "success", "lockout")
    try writeUseCases("checkout", "success")
    try writeUseCases("authentication", "sso")
    try writeUseCases("auth", "reset")
  }

  private func writeUseCases(
    _ prefix: String,
    _ locals: String...,
  ) throws {
    try fixture.write(
      "use-cases/\(prefix).yml",
      "prefix: \(prefix)\nuse_cases:\n" + locals.map { local in
        YAMLSamples.useCase(local)
      }.joined(),
    )
  }

  private func groups(_ body: String) throws -> [UseCaseGroup] {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups:\n" + body)

    return try fixture.loaded().groups
  }

  private func members(
    of name: String,
    _ body: String,
  ) throws -> [String] {
    let found = try groups(body).first { group in
      group.name.text == name
    }

    return try #require(found).members
  }

  private func problems(_ body: String) throws -> [String] {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups:\n" + body)

    return fixture.problemsIncludingLinks()
  }

  private func warnings(_ body: String) throws -> [String] {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups:\n" + body)

    return try fixture.loaded().rootFileWarnings.map(\.description)
  }

  // MARK: - Membership

  @Test
  func `a workspace with no groups file has no groups`() throws {
    let loaded = try fixture.loaded()

    #expect(loaded.groups.isEmpty)
    #expect(loaded.rootFileWarnings.isEmpty)
  }

  @Test
  func `a prefix selects by whole segments: app dot auth is never app dot authentication`(
  ) throws {
    #expect(try members(of: "g", "  g:\n    include: { prefixes: [app.auth] }\n") == [
      "app.auth.reset",
    ])
  }

  @Test
  func `a prefix selects the use case it names as well as everything under it`() throws {
    #expect(try members(of: "g", "  g:\n    include: { prefixes: [app.login.success] }\n") == [
      "app.login.success",
    ])
  }

  @Test
  func `globs select whole segments`() throws {
    let text = "  one:\n    include: { globs: [app.*.success] }\n"
      + "  any:\n    include: { globs: ['**.success'] }\n"

    #expect(try members(of: "one", text) == ["app.checkout.success", "app.login.success"])
    #expect(try members(of: "any", text) == ["app.checkout.success", "app.login.success"])
  }

  @Test
  func `exclude always wins, and an omitted include means every use case`() throws {
    let text = "  g:\n    exclude: { prefixes: [app.login], ids: [app.auth.reset] }\n"

    #expect(try members(of: "g", text) == ["app.authentication.sso", "app.checkout.success"])
  }

  @Test
  func `include and exclude may overlap without a word`() throws {
    let text = "  g:\n    include: { prefixes: [app.login] }\n"
      + "    exclude: { ids: [app.login.lockout] }\n"

    #expect(try members(of: "g", text) == ["app.login.success"])
    #expect(try fixture.loaded().rootFileWarnings.isEmpty)
  }

  @Test
  func `overlapping selectors across kinds give each member once`() throws {
    let text = "  g:\n    include: { ids: [app.login.success], prefixes: [app.login] }\n"

    #expect(try members(of: "g", text) == ["app.login.lockout", "app.login.success"])
  }

  @Test
  func `a DRAFT use case is a member like any other`() throws {
    try fixture.write(
      "use-cases/draft.yml",
      "prefix: draft\nuse_cases:\n  - id: wip\n    title: Work in progress\n",
    )

    #expect(try members(of: "g", "  g:\n    include: { prefixes: [app.draft] }\n") == [
      "app.draft.wip",
    ])
  }

  @Test
  func `groups keep the order written and their description`() throws {
    let found = try groups(
      "  zeta:\n    description: Last in the alphabet.\n    include: { prefixes: [app.auth] }\n"
        + "  alpha:\n    include: { prefixes: [app.auth] }\n",
    )

    #expect(found.map(\.name.text) == ["zeta", "alpha"])
    #expect(found.first?.description == "Last in the alphabet.")
    #expect(found.last?.description == nil)
  }

  @Test
  func `a glob of ten thousand double stars loads and selects, with no limit on its length`(
  ) throws {
    let glob = Array(repeating: "**", count: 10000).joined(separator: ".")

    let body = "  g:\n    include: { globs: ['" + glob + ".success'] }\n"
    let found = try members(of: "g", body)

    #expect(found == ["app.checkout.success", "app.login.success"])
  }

  // MARK: - INVALID

  @Test(arguments: [
    ("  g:\n    include: { ids: [app.nope] }\n", "no use case 'app.nope'"),
    ("  g:\n    exclude: { ids: [app.nope] }\n", "no use case 'app.nope'"),
    ("  g:\n    include: { globs: [app.log*] }\n", "is not allowed at groups/g/include/globs/0"),
    ("  g:\n    include: { prefixes: [App] }\n", "is not allowed at groups/g/include/prefixes/0"),
    ("  Bad:\n    include: { ids: [app.auth.reset] }\n", "is not allowed at groups"),
    ("  g:\n    members: [app.auth.reset]\n", "Additional properties"),
    ("  g:\n    include: { tags: [x] }\n", "Additional properties"),
    ("  g:\n    include: {}\n", "include selects nothing"),
    ("  g:\n    include: { ids: [] }\n", "include selects nothing"),
    ("  g:\n    include: { ids: [], prefixes: [], globs: [] }\n", "include selects nothing"),
  ])
  func `what makes the groups file invalid`(
    body: String,
    reason: String,
  ) throws {
    let found = try problems(body)

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("use-case-groups.yml: ") == true)
    #expect(found.first?.contains(reason) == true)
  }

  @Test(arguments: [
    "",
    "schema_version: 1\n",
    "schema_version: 2\ngroups: {}\n",
    "schema_version: 1\ngroups: {}\nextra: 1\n",
    "schema_version: 1\ngroups: [\n",
    "schema_version: 1\ngroups:\n  g: {}\ngroups: {}\n",
  ])
  func `a file that is not a groups file is refused`(text: String) throws {
    try fixture.write("use-case-groups.yml", text)

    let found = fixture.problemsIncludingLinks()

    #expect(!found.isEmpty)
    #expect(
      found.allSatisfy { line in
        line.hasPrefix("use-case-groups.yml")
      },
    )
  }

  @Test
  func `a folder or a symlink with the name is refused, not skipped`() throws {
    try fixture.directory.makeDirectory("use-case-groups.yml")

    let found = fixture.problemsIncludingLinks()

    #expect(found.count == 1)
    #expect(found.mentions("must be a regular file"))
  }

  @Test
  func `a file spelled in another case is refused naming its spelling, on every system`() throws {
    try fixture.write("Use-Case-Groups.yml", "schema_version: 1\ngroups: {}\n")

    let found = fixture.problemsIncludingLinks()

    #expect(found.count == 1)
    #expect(found.mentions("'Use-Case-Groups.yml' is not spelled use-case-groups.yml"))
  }

  @Test(.enabled(if: TemporaryDirectory.allowsNamesDifferingInCase))
  func `a lookalike beside the real file is refused and the real file is still read`() throws {
    try fixture.write("Use-Case-Groups.yml", "schema_version: 1\ngroups: {}\n")
    try fixture.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  g:\n    include: { ids: [app.nope] }\n",
    )

    let found = fixture.problemsIncludingLinks()

    #expect(found.count == 2)
    #expect(found.mentions("'Use-Case-Groups.yml' is not spelled"))
    #expect(found.mentions("no use case 'app.nope'"))
  }

  @Test
  func `a folder spelled in another case is no lookalike`() throws {
    try fixture.directory.makeDirectory("Use-Case-Groups.yml")

    #expect(fixture.problemsIncludingLinks().isEmpty)
  }

  @Test(arguments: ["use-case-groups.yml", "Use-Case-Groups.yml"])
  func `a groups file in a child scope is refused, never ignored`(name: String) throws {
    try fixture.write("svc/use-cases.yml", YAMLSamples.child(prefix: "svc"))
    try fixture.write("svc/\(name)", "schema_version: 1\ngroups: {}\n")

    let found = fixture.problemsIncludingLinks()

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("svc/\(name): ") == true)
  }

  @Test
  func `a child scope's groups file is refused for what it is, not as a lookalike`() throws {
    try fixture.write("svc/use-cases.yml", YAMLSamples.child(prefix: "svc"))
    try fixture.write("svc/use-case-groups.yml", "schema_version: 1\ngroups: {}\n")

    #expect(fixture.problemsIncludingLinks().mentions("groups are root-only"))
  }

  @Test
  func `a root that cannot be listed is a failure, never no groups file`() throws {
    let root = WorkspaceRoot(
      directory: fixture.directory.url,
      settings: ScopeSettings(
        isRoot: true,
        useCasesDirectory: .root,
        excludes: [],
      ),
    )
    let loader = try GroupsLoader(
      fileSystem: LocalFileSystem(),
      yamlReader: StrictYAMLReader(),
      schema: BundledSchemaLoader().loadChecker(for: .useCaseGroups),
      resolver: GroupResolver(),
      locator: OwnedFileLocator(fileSystem: UnlistableFileSystem()),
    )

    let result = loader.load(
      in: root,
      scopes: [],
      among: .all([]),
    )

    #expect(result.groups.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics.first?.code == "unreadable-groups")
  }

  @Test
  func `several problems are all reported, sorted`() throws {
    let found = try problems(
      "  b:\n    include: {}\n  a:\n    include: { ids: [app.nope] }\n",
    )

    #expect(found.count == 2)
    #expect(found == found.sorted())
  }

  @Test
  func `when a use case file is broken only the structure of the groups file is checked`(
  ) throws {
    try fixture.write("use-cases/broken.yml", "use_cases: 5\n")

    // The ids might be in the file that could not be read, so none of them is called missing.
    let ids = try problems("  g:\n    include: { ids: [app.broken.thing] }\n")
    let shape = try problems("  g:\n    include: {}\n")

    #expect(ids.count == 1)
    #expect(ids.first?.hasPrefix("use-cases/broken.yml") == true)
    #expect(shape.count == 2)
    #expect(shape.mentions("include selects nothing"))
  }

  // MARK: - Warnings

  @Test
  func `what only warns`() throws {
    let found = try warnings(
      "  g:\n    include: { prefixes: [app.nothing, app.login, app.login], "
        + "globs: ['app.zzz.*'] }\n"
        + "  empty:\n    include: { ids: [app.auth.reset] }\n"
        + "    exclude: { ids: [app.auth.reset] }\n",
    )

    #expect(found.mentions("prefix 'app.nothing' matches nothing"))
    #expect(found.mentions("glob 'app.zzz.*' matches nothing"))
    #expect(found.mentions("duplicate selector 'app.login'"))
    #expect(found.mentions("group 'empty' has no members"))
    #expect(found.count == 4)
  }

  @Test
  func `an empty groups table, an empty exclude and empty lists warn`() throws {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")
    #expect(try fixture.loaded().rootFileWarnings.map(\.description) == [
      "use-case-groups.yml: groups is empty: no group is defined",
    ])

    let text = try warnings(
      "  g:\n    include: { prefixes: [app.login], ids: [] }\n    exclude: {}\n"
        + "  h:\n    exclude: { globs: [] }\n",
    )

    #expect(text.mentions("groups/g/include/ids is empty"))
    #expect(text.mentions("groups/g/exclude is empty"))
    #expect(text.mentions("groups/h/exclude/globs is empty"))
  }

  @Test
  func `duplicate ids and globs warn like duplicate prefixes`() throws {
    let found = try warnings(
      "  g:\n    include: { ids: [app.auth.reset, app.auth.reset], "
        + "globs: ['**.reset', '**.reset'] }\n",
    )

    #expect(found.count == 2)
    #expect(
      found.allSatisfy { line in
        line.contains("duplicate selector")
      },
    )
  }

  @Test
  func `warnings are sorted, and a warning never makes the workspace invalid`() throws {
    let found = try warnings(
      "  z:\n    include: { prefixes: [app.nothing] }\n"
        + "  a:\n    include: { prefixes: [app.also-nothing] }\n",
    )

    #expect(found == found.sorted())
    #expect(found.count == 4)
    #expect(try fixture.loaded().groups.map(\.name.text) == ["z", "a"])
  }

  @Test
  func `the warnings of the groups are not among the load's own warnings`() throws {
    try fixture.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  g:\n    include: { prefixes: [app.nothing] }\n",
    )

    #expect(try fixture.loaded().warnings.isEmpty)
  }
}
