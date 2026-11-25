import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceLoaderRootTests {
  @Test
  func `a folder below the root finds the root by walking up`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases/ui.yml", YAMLSamples.file(YAMLSamples.useCase()))
    try fixture.directory.makeDirectory("src/deep")

    let workspace = try fixture.load(
      from: .searchingUpward(from: fixture.directory.location(of: "src/deep")),
    )

    #expect(workspace.root == fixture.directory.url)
    #expect(workspace.useCases.count == 1)
  }

  @Test
  func `a child scope is passed over on the way up`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("svc/use-cases.yml", YAMLSamples.child(prefix: "svc"))
    try fixture.write("svc/use-cases/a.yml", YAMLSamples.file(YAMLSamples.useCase("a")))

    let workspace = try fixture.load(
      from: .searchingUpward(from: fixture.directory.location(of: "svc")),
    )

    #expect(workspace.useCases.map(\.identifier.text) == ["app.svc.a"])
  }

  @Test
  func `no root above the start is refused with a way forward`() throws {
    let directory = try TemporaryDirectory()
    let loader = WorkspaceLoader()

    do {
      _ = try loader.load(from: .searchingUpward(from: directory.url))
      Issue.record("a workspace was found")
    } catch {
      guard case let .noWorkspace(message) = error else {
        Issue.record("unexpected refusal: \(error)")
        return
      }

      #expect(message.contains("no use-cases.yml with root: true"))
      #expect(message.contains("use-cases init"))
    }
  }

  @Test
  func `naming a child scope is refused`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("svc/use-cases.yml", YAMLSamples.child(prefix: "svc"))

    let problems = fixture.problems(from: .workspace(fixture.directory.location(of: "svc")))

    #expect(problems.count == 1)
    #expect(problems.first?.contains("child scope") == true)
  }

  @Test
  func `a root that does not say root true is refused`() throws {
    let fixture = try WorkspaceFixture(rootConfiguration: "schema_version: 1\nprefix: app\n")

    #expect(fixture.problems().first?.contains("root: true") == true)
  }

  @Test(arguments: ["Use-Cases.yml", "USE-CASES.YML"])
  func `a root file spelled in another case is refused, naming the spelling on disk`(
    name: String,
  ) throws {
    let directory = try TemporaryDirectory()
    try directory.write(name, YAMLSamples.root)
    let loader = WorkspaceLoader()

    do {
      _ = try loader.load(from: .workspace(directory.url))
      Issue.record("the folder was accepted as a root")
    } catch {
      #expect(error.message.contains(name))
    }
  }

  @Test
  func `a root configuration with several problems lists each, sorted, relative to the root`()
    throws
  {
    let fixture = try WorkspaceFixture(
      rootConfiguration: "schema_version: 2\nroot: true\nprefix: App\n",
    )

    let problems = fixture.problems()

    #expect(problems.count == 2)
    #expect(problems.allSatisfy { problem in problem.hasPrefix("use-cases.yml: ") })
    #expect(problems.first?.contains("schema_version") == true)
    #expect(problems.last?.contains("prefix") == true)
  }

  @Test
  func `a root configuration found by searching names its file in full`() throws {
    let fixture = try WorkspaceFixture(
      rootConfiguration: "schema_version: 2\nroot: true\nprefix: App\n",
    )
    let file = fixture.directory.location(of: "use-cases.yml").path

    let problems = fixture.problems(
      from: .searchingUpward(from: fixture.directory.url),
    )

    #expect(problems.count == 2)
    #expect(problems.allSatisfy { problem in problem.hasPrefix("\(file): ") })
    #expect(problems.first?.contains("schema_version") == true)
  }

  @Test
  func `a root configuration that is not YAML is refused with its line, relative to the root`()
    throws
  {
    let fixture = try WorkspaceFixture(rootConfiguration: "schema_version: 1\nroot: [\n")

    let problem = try #require(fixture.problems().first)

    #expect(problem.hasPrefix("use-cases.yml:"))
    #expect(problem.contains("not valid YAML"))
  }
}
