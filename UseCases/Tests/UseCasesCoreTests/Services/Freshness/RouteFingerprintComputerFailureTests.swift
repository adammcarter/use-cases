import Foundation
import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerFailureTests {
  private func fixture(resources: [String]) throws -> FreshnessFixture {
    try FreshnessFixture(
      definitions: FreshnessSamples.definitions(resources: resources),
    )
  }

  @Test
  func `a missing resource file makes the workspace INVALID and is filed under the definition`()
    throws
  {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/users.json")])

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(
      result.problems == [
        "use-cases/toggle.yml: route 'unit-tests' of use case 'app.toggle' has the resource "
          + "file 'fixtures/users.json', which is missing",
      ],
    )
  }

  @Test
  func `a glob that matches nothing says so and names the pattern`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])

    let problems = try fixture.fingerprints().problems

    #expect(problems.count == 1)
    #expect(problems.first?.hasPrefix("use-cases/toggle.yml: route 'unit-tests'") == true)
    #expect(problems.first?
      .contains("the resource glob 'fixtures/*.json', which matches nothing") == true)
  }

  @Test
  func `a resource spelled differently on disk is refused`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("Fixtures/users.json")])
    try fixture.write("fixtures/users.json", "{}")

    let problems = try fixture.fingerprints().problems

    #expect(problems.count == 1)
    #expect(problems.first?.contains("is spelled 'fixtures' on disk") == true)
  }

  @Test
  func `a resource behind a symlink is refused`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("linked/users.json")])
    try fixture.write("real/users.json", "{}")
    try fixture.workspace.directory.symlink(
      "linked",
      to: "real",
    )

    let problem = try #require(fixture.fingerprints().problems.first)

    #expect(problem.contains("a symlink, which is never followed"))
  }

  @Test
  func `a resource that is a folder is not a file`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures")])
    try fixture.write("fixtures/a.json", "{}")

    let problem = try #require(fixture.fingerprints().problems.first)

    #expect(problem.contains("the resource file 'fixtures', which is a folder, not a file"))
  }

  @Test
  func `a DRAFT use case's resources are checked too`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        isReady: false,
        resources: [FreshnessSamples.file("nope.json")],
      ),
    )

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.problems.count == 1)
  }

  @Test
  func `every problem is reported, not only the first`() throws {
    let fixture = try fixture(
      resources: [
        FreshnessSamples.file("a.json"),
        FreshnessSamples.file("b.json"),
        FreshnessSamples.glob("none/*.json"),
      ],
    )

    #expect(try fixture.fingerprints().problems.count == 3)
  }

  @Test
  func `a malformed resource pattern is refused when the workspace loads`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("build**")])

    let problems = fixture.workspace.problems()

    #expect(problems.contains { problem in
      problem.contains("pattern")
    })
  }

  @Test
  func `links that did not resolve withhold every fingerprint and carry their problems`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("config", file: "missing.yml")],
        resources: [FreshnessSamples.file("nope.json")],
      ),
    )

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(result.problems.count == 2)
    #expect(result.problems.contains { problem in
      problem.contains("missing.yml")
    })
    #expect(result.problems.contains { problem in
      problem.contains("nope.json")
    })
  }

  @Test
  func `a file that shrank after its links were resolved is a problem, not a crash`() throws {
    let fixture = try FreshnessFixture()
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)

    try fixture.write("src/app.swift", "x")
    let result = RouteFingerprintComputer().fingerprints(of: loaded, links: links)

    #expect(result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(result.problems.first?.hasPrefix("src/app.swift: the file changed") == true)
  }

  @Test
  func `a file that vanished after its links were resolved is a problem`() throws {
    let fixture = try FreshnessFixture()
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)

    try FileManager.default.removeItem(
      at: fixture.workspace.directory.location(of: "src/app.swift"),
    )
    let result = RouteFingerprintComputer().fingerprints(of: loaded, links: links)

    #expect(result.isInvalid)
    #expect(result.problems.first?.hasPrefix("src/app.swift: the file is missing") == true)
  }

  @Test
  func `a resource that vanished after it was resolved is a problem`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("a.json")])
    try fixture.write("a.json", "{}")
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)

    try FileManager.default.removeItem(at: fixture.workspace.directory.location(of: "a.json"))
    let result = RouteFingerprintComputer().fingerprints(of: loaded, links: links)

    #expect(result.isInvalid)
  }
}
