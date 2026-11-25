import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceDiscovererReadWholeTests {
  @Test
  func `a configured exclusion reaching inside a use_cases_dir is invalid and named`() throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nexclude: use-cases/drafts/**, use-cases/old.yml\n",
    )
    try fixture.directory.write("use-cases/keep.yml")
    try fixture.directory.write("use-cases/old.yml")
    try fixture.directory.write("use-cases/drafts/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/keep.yml"])
    #expect(
      discovery.diagnosticSummaries == [
        "use-cases/drafts: exclusion-inside-definitions",
        "use-cases/old.yml: exclusion-inside-definitions",
      ],
    )

    let messages = discovery.diagnostics.map(\.message)
    #expect(messages[0].contains("discovery.exclude 'use-cases/drafts/**'"))
    #expect(messages[0].contains("use_cases_dir 'use-cases'"))
    #expect(messages[1].contains("discovery.exclude 'use-cases/old.yml' reaches inside"))
    #expect(messages[1].contains("a use_cases_dir is read whole"))
  }

  @Test(arguments: [".git", ".hg", ".svn", ".bzr", ".jj", ".use-cases"])
  func `a built-in exclusion inside a use_cases_dir is invalid and named`(folder: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/keep.yml")
    try fixture.directory.write("use-cases/sub/\(folder)/c.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/keep.yml"])
    #expect(
      discovery.diagnosticSummaries == ["use-cases/sub/\(folder): exclusion-inside-definitions"],
    )

    let message = try #require(discovery.diagnostics.first?.message)
    #expect(message.contains("the built-in exclusion '**/\(folder)/**'"))
    #expect(!discovery.isValid)
  }

  @Test
  func `an excluded folder elsewhere that holds a scope is still never entered`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nexclude: generated/**\n")
    try fixture.scope("generated/pkg")
    try fixture.directory.write("generated/pkg/use-cases/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a use_cases_dir spelt in another case than the folder is invalid, naming the folder`(
  ) throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: Specs\n")
    try fixture.directory.write("specs/a.yml")
    try fixture.directory.write("specs/child/use-cases.yml")
    try fixture.directory.write("specs/child/use-cases/b.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-spelled-differently"])

    let message = try #require(discovery.diagnostics.first?.message)
    #expect(message.contains("'Specs' is not found as written; on disk: \"specs\""))
    #expect(!discovery.isValid)
  }

  @Test
  func `the default use-cases folder spelt in capitals on disk is invalid`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("USE-CASES/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-spelled-differently"])
    #expect(discovery.diagnostics.first?.message.contains("on disk: \"USE-CASES\"") == true)
  }

  @Test
  func `a use_cases_dir spelt in one Unicode form on disk and another in the config is invalid`()
    throws
  {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: caf\u{E9}\n")
    try fixture.directory.write("cafe\u{301}/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-spelled-differently"])
  }

  @Test
  func `a segment spelt wrongly part-way along a use_cases_dir is invalid`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: docs/Uc\n")
    try fixture.directory.write("docs/uc/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-spelled-differently"])
    #expect(discovery.diagnostics.first?.message.contains("'docs/Uc'") == true)
  }

  @Test
  func `a use_cases_dir spelt exactly as on disk is read`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: Specs\n")
    try fixture.directory.write("Specs/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["Specs/a.yml"])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test(arguments: ["a.yml", "b.yaml", "c.YML"])
  func `a named pipe with a YAML name inside a use_cases_dir is invalid and never opened`(
    name: String,
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/real.yml")
    try fixture.directory.makeFIFO("use-cases/sub/\(name)")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/real.yml"])
    #expect(discovery.diagnosticSummaries == ["use-cases/sub/\(name): not-a-file-in-definitions"])
    #expect(!discovery.isValid)
  }

  @Test
  func `a named pipe without a YAML name inside a use_cases_dir is ignored`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.makeFIFO("use-cases/events.log")

    let discovery = try fixture.discover()

    #expect(discovery.diagnostics.isEmpty)
  }

  @Test(arguments: ["bad\\name.yml", "bad\\folder/inner.yml", "plain.txt\u{7}x"])
  func `a name inside a use_cases_dir that no path can spell is invalid`(name: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/real.yml")
    try fixture.directory.write("use-cases/\(name)")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/real.yml"])
    #expect(discovery.diagnosticSummaries == ["use-cases: unspellable-name-in-definitions"])
    #expect(!discovery.isValid)
  }
}
