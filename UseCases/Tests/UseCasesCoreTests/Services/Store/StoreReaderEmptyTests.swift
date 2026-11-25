import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderEmptyTests {
  let fixture: StoreFixture

  init() throws {
    fixture = try StoreFixture()
  }

  @Test
  func `a workspace with no store has an empty history`() throws {
    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.isEmpty)
    #expect(history.unfinishedRuns.isEmpty)
  }

  @Test(arguments: [
    ".use-cases",
    ".use-cases/runs",
  ])
  func `an empty store has an empty history`(folder: String) throws {
    try fixture.directory.makeDirectory(folder)

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.isEmpty)
    #expect(history.unfinishedRuns.isEmpty)
  }

  @Test
  func `a store holding only an allocation file and an index has an empty history`() throws {
    try fixture.write(".use-cases/run-order.json", StoreSamples.runOrder.json)
    try fixture.write(".use-cases/index.sqlite", "not evidence")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.isEmpty)
  }

  @Test
  func `a lookup in an empty history finds nothing`() throws {
    let history = try StoreReader().readHistory(in: fixture.workspace)
    let useCase = try UseCaseIdentifier(validating: StoreSamples.useCase)
    let route = try RouteIdentifier(validating: StoreSamples.route)
    let fingerprint = try RouteFingerprint(validating: StoreSamples.fingerprint)

    #expect(history.results(useCase: useCase, route: route).isEmpty)
    #expect(history.latestResult(useCase: useCase, route: route) == nil)
    #expect(history.latestResult(useCase: useCase, route: route, fingerprint: fingerprint) == nil)
  }

  @Test(arguments: [".use-cases", ".use-cases/runs"])
  func `a store place that is a file is a storage error`(place: String) throws {
    if place == ".use-cases/runs" {
      try fixture.directory.makeDirectory(".use-cases")
    }
    try fixture.write(place, "")

    let error = #expect(throws: StoreReadingError.self) {
      try StoreReader().readHistory(in: fixture.workspace)
    }

    #expect(error == .damaged([
      StoreProblem(location: place, reason: .notAFolder),
    ]))
  }

  @Test
  func `a store that is a symlink is not followed`() throws {
    try fixture.directory.makeDirectory("elsewhere/runs")
    try fixture.directory.symlink(".use-cases", to: "elsewhere")

    let error = #expect(throws: StoreReadingError.self) {
      try StoreReader().readHistory(in: fixture.workspace)
    }

    #expect(error == .damaged([
      StoreProblem(location: ".use-cases", reason: .notAFolder),
    ]))
  }

  @Test(.enabled(if: getuid() != 0, "permissions do not stop root"))
  func `a runs folder that cannot be listed is a storage error naming it`() throws {
    try fixture.directory.makeDirectory(".use-cases/runs")
    let runs = fixture.directory.location(of: ".use-cases/runs").path
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: runs)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runs)
    }

    let error = #expect(throws: StoreReadingError.self) {
      try StoreReader().readHistory(in: fixture.workspace)
    }

    guard case let .damaged(problems)? = error, let problem = problems.first else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return
    }
    #expect(problem.location == ".use-cases/runs")
    #expect(problem.description.contains("cannot be read"))
  }
}
