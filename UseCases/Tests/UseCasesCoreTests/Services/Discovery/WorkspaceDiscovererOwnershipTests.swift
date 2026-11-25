import Testing
@testable import UseCasesCore

struct WorkspaceDiscovererOwnershipTests {
  @Test
  func `a scope inside the root's use_cases_dir is invalid and the message names it`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/billing/invoice.yml")
    try fixture.scope("use-cases/billing", "")

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == [
      "use-cases/billing/use-cases.yml: scope-inside-definitions",
    ])

    let diagnostic = try #require(discovery.diagnostics.first)
    #expect(diagnostic.message.contains("'use-cases/billing/use-cases.yml'"))
    #expect(diagnostic.message.contains("which holds the root scope's definitions"))
    #expect(!discovery.isValid)
  }

  @Test
  func `the scope inside is not entered by its parent, so no definition is owned twice`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/mine.yml")
    try fixture.directory.write("use-cases/billing/theirs.yml")
    try fixture.scope("use-cases/billing", "use_cases_dir: .\n")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/mine.yml"])
    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "use-cases/billing"])
  }

  @Test(arguments: ["use-cases/a/b/c", "use-cases/x", "use-cases/deep/er/still"])
  func `a scope at any depth inside the use_cases_dir is invalid`(folder: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope(folder)

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["\(folder)/use-cases.yml: scope-inside-definitions"])
  }

  @Test
  func `a scope inside a scope inside the use_cases_dir is invalid too`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("use-cases/outer")
    try fixture.scope("use-cases/outer/inner")

    let discovery = try fixture.discover()

    #expect(
      discovery.diagnosticSummaries == [
        "use-cases/outer/inner/use-cases.yml: scope-inside-definitions",
        "use-cases/outer/use-cases.yml: scope-inside-definitions",
      ],
    )
  }

  @Test
  func `a scope inside a child scope's use_cases_dir names that scope as the holder`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("services/pay")
    try fixture.scope("services/pay/use-cases/refunds")

    let discovery = try fixture.discover()

    let diagnostic = try #require(discovery.diagnostics.first)
    #expect(diagnostic.file.text == "services/pay/use-cases/refunds/use-cases.yml")
    #expect(diagnostic.message.contains("which holds the definitions of scope 'services/pay'"))
    #expect(discovery.diagnostics.count == 1)
  }

  @Test
  func `a scope beside the use_cases_dir is fine and owns its own definitions`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/root.yml")
    try fixture.scope("payments")
    try fixture.directory.write("payments/use-cases/card.yml")

    let discovery = try fixture.discover()

    #expect(discovery.diagnostics.isEmpty)
    #expect(discovery.definitionTexts["."] == ["use-cases/root.yml"])
    #expect(discovery.definitionTexts["payments"] == ["payments/use-cases/card.yml"])
  }

  @Test
  func `a scope in the folder of a similarly named use_cases_dir is not inside it`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: use\n")
    try fixture.scope("use-cases-extra")
    try fixture.scope("user")

    let discovery = try fixture.discover()

    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a use_cases_dir holding its own scope's use-cases file is invalid`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: .\n")
    try fixture.directory.write("ui.yml")

    let discovery = try fixture.discover()

    let diagnostic = try #require(discovery.diagnostics.first)
    #expect(diagnostic.file.text == "use-cases.yml")
    #expect(diagnostic.code.text == "definitions-hold-configuration")
    #expect(diagnostic.message.contains("must not contain this scope's own use-cases.yml"))
    #expect(discovery.definitionTexts["."] == [])
    #expect(!discovery.isValid)
  }

  @Test
  func `a child scope whose use_cases_dir is its own folder is invalid`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pay", "use_cases_dir: .\n")

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["pay/use-cases.yml: definitions-hold-configuration"])
  }

  @Test
  func `with the root's use_cases_dir as dot every child scope is inside it`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: .\n")
    try fixture.scope("pay")

    let discovery = try fixture.discover()

    #expect(
      discovery.diagnosticSummaries == [
        "pay/use-cases.yml: scope-inside-definitions",
        "use-cases.yml: definitions-hold-configuration",
      ],
    )
  }

  @Test
  func `two scopes claiming the same use_cases_dir are reported once, on the later one`() throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nuse_cases_dir: services/pay/use-cases\n",
    )
    try fixture.scope("services/pay")
    try fixture.directory.write("services/pay/use-cases/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["services/pay/use-cases.yml: definitions-overlap"])

    let message = try #require(discovery.diagnostics.first?.message)
    #expect(message.contains("'services/pay/use-cases'"))
    #expect(message.contains("the root scope"))
  }

  @Test
  func `sibling scopes that spell their use_cases_dir alike do not overlap`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("a", "use_cases_dir: x\n")
    try fixture.scope("b", "use_cases_dir: x\n")
    try fixture.scope("c", "use_cases_dir: x\n")

    let discovery = try fixture.discover()

    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a use_cases_dir inside another scope's use_cases_dir is reported on the inner scope`(
  ) throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nuse_cases_dir: services/pay/use-cases/specs\n",
    )
    try fixture.scope("services/pay", "use_cases_dir: use-cases/specs/more\n")

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["services/pay/use-cases.yml: definitions-overlap"])
  }

  @Test
  func `use_cases_dirs that merely share a name prefix do not overlap`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: specs\n")
    try fixture.scope("pay", "use_cases_dir: specs-pay\n")

    let discovery = try fixture.discover()

    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a use_cases_dir that is another scope's own folder reads none of that scope's files`(
  ) throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: services\n")
    try fixture.scope("services")
    try fixture.directory.write("services/notes.yml")
    try fixture.directory.write("services/use-cases/own.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.definitionTexts["services"] == ["services/use-cases/own.yml"])
    #expect(discovery.diagnosticSummaries == ["services/use-cases.yml: scope-inside-definitions"])
  }
}
