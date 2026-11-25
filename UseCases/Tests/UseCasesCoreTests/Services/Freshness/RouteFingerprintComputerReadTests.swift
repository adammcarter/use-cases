import Foundation
import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerReadTests {
  @Test
  func `a file that is linked, a resource and named twice is read once`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("config", file: "config/app.yml")],
        resources: [
          FreshnessSamples.file("src/app.swift"),
          FreshnessSamples.file("config/app.yml"),
          FreshnessSamples.glob("config/*.yml"),
        ],
      ),
    )
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    try fixture.write("config/app.yml", "a: 1\n")
    let logs = try TemporaryDirectory()
    let counting = try CountingFileSystem(log: logs.location(of: "reads.log"))
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)

    let result = RouteFingerprintComputer(fileSystem: counting).fingerprints(
      of: loaded,
      links: links,
    )
    let reads = try counting.reads()

    #expect(!result.isInvalid, "problems: \(result.problems)")
    #expect(reads.count == 2)
    #expect(reads.values.allSatisfy { count in
      count == 1
    })
  }

  @Test
  func `reading the same workspace again reads again: nothing outlives a call`() throws {
    let fixture = try FreshnessFixture()
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    let logs = try TemporaryDirectory()
    let counting = try CountingFileSystem(log: logs.location(of: "reads.log"))
    let computer = RouteFingerprintComputer(fileSystem: counting)
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)

    _ = computer.fingerprints(of: loaded, links: links)
    _ = computer.fingerprints(of: loaded, links: links)

    #expect(try counting.reads().values.allSatisfy { count in
      count == 2
    })
  }

  @Test(.enabled(if: getuid() != 0, "permissions do not stop root"))
  func `an unreadable resource says so once, with the workspace path and no absolute path`()
    throws
  {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(resources: [FreshnessSamples.file("a.json")]),
    )
    try fixture.write("a.json", "{}")
    let loaded = try fixture.workspace.loaded()
    let links = LinkResolver().resolveLinks(in: loaded)
    let location = fixture.workspace.directory.location(of: "a.json")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: location.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: location.path,
      )
    }

    let problems = RouteFingerprintComputer().fingerprints(of: loaded, links: links).problems
    let problem = try #require(problems.first)

    #expect(problems.count == 1)
    #expect(problem.contains("the resource file 'a.json', which cannot be read:"))
    #expect(!problem.contains(fixture.workspace.directory.url.path))
    #expect(problem.components(separatedBy: "cannot be read").count == 2)
  }
}
