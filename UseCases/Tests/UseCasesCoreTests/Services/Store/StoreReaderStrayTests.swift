import Foundation
import Testing
@testable import UseCasesCore

struct StoreReaderStrayTests {
  let fixture: StoreFixture

  init() throws {
    fixture = try StoreFixture()
    try fixture.sealRecord(StoreFixture.identifier(1))
  }

  @Test(arguments: [
    "latest",
    "backup",
    "0000000000000000000000000000002A",
    "0000000000000000000000000000002",
    "000000000000000000000000000000002a",
    "00000000000000000000000000000000",
    "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
    ".tmp",
    "tmp-abc",
  ])
  func `a folder that is not a run id is a storage error`(name: String) throws {
    try fixture.directory.makeDirectory(".use-cases/runs/\(name)")

    #expect(try fixture.problems() == [".use-cases/runs/\(name) is not a run folder"])
  }

  @Test
  func `a stray file in runs is a storage error`() throws {
    try fixture.write(".use-cases/runs/.DS_Store", "")

    #expect(try fixture.problems() == [".use-cases/runs/.DS_Store is not a run folder"])
  }

  @Test
  func `a symlink named like a run is not followed and is a storage error`() throws {
    let name = StoreFixture.identifier(2)
    try fixture.sealRecord(StoreFixture.identifier(3))
    try fixture.directory.symlink(".use-cases/runs/\(name)", to: StoreFixture.identifier(3))

    #expect(try fixture.problems() == [".use-cases/runs/\(name) is not a run folder"])
  }

  @Test
  func `a file named like a run is a storage error`() throws {
    let name = StoreFixture.identifier(2)
    try fixture.write(".use-cases/runs/\(name)", "")

    #expect(try fixture.problems() == [".use-cases/runs/\(name) is not a run folder"])
  }

  @Test
  func `every stray is reported with every corrupt run, sorted`() throws {
    try fixture.directory.makeDirectory(".use-cases/runs/zeta")
    try fixture.directory.makeDirectory(".use-cases/runs/alpha")
    let broken = StoreFixture.identifier(9)
    try fixture.sealRecord(broken)
    try fixture.write("\(StoreFixture.folder(broken))/results.jsonl", "{}\n")

    let found = try fixture.problems()

    #expect(found.count == 3)
    #expect(found.first == ".use-cases/runs/\(broken)/results.jsonl is corrupt: " +
      "it is not the file completion.json sealed: its digest differs")
    #expect(found.dropFirst().first == ".use-cases/runs/alpha is not a run folder")
    #expect(found.last == ".use-cases/runs/zeta is not a run folder")
  }

  @Test
  func `a stray folder refuses the whole read though every run is fine`() throws {
    try fixture.directory.makeDirectory(".use-cases/runs/latest")

    #expect(throws: StoreReadingError.self) {
      try StoreReader().readHistory(in: fixture.workspace)
    }
  }

  @Test
  func `a run with no completion marker is listed and never evidence`() throws {
    let unfinished = StoreFixture.identifier(5)
    try fixture.startRun(unfinished)
    try fixture.write(
      "\(StoreFixture.folder(unfinished))/results.jsonl",
      "garbage that is not json",
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.unfinishedRuns.map(\.description) == ["run \(unfinished) never finished"])
    #expect(history.runs.map(\.identifier.text) == [StoreFixture.identifier(1)])
  }

  @Test
  func `an empty run folder is an unfinished run`() throws {
    let name = StoreFixture.identifier(5)
    try fixture.directory.makeDirectory(StoreFixture.folder(name))

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.unfinishedRuns.map(\.identifier.text) == [name])
  }

  @Test
  func `an unfinished run's result is not in any lookup`() throws {
    let unfinished = StoreFixture.identifier(5)
    try fixture.startRun(unfinished)
    try fixture.sealRecord(StoreFixture.identifier(3), status: "fail")
    try fixture.write(
      "\(StoreFixture.folder(unfinished))/results.jsonl",
      StoreSamples.recordedResult().json + "\n",
    )

    let history = try StoreReader().readHistory(in: fixture.workspace)
    let useCase = try UseCaseIdentifier(validating: StoreSamples.useCase)
    let route = try RouteIdentifier(validating: StoreSamples.route)

    let newest = try #require(history.latestResult(useCase: useCase, route: route))
    #expect(newest.run.text == StoreFixture.identifier(3))
  }

  @Test(arguments: ["directory", "symlink"])
  func `a completion marker that is not a file is corruption, not an unsealed run`(
    kind: String,
  ) throws {
    let name = StoreFixture.identifier(5)
    try fixture.startRun(name)
    let marker = "\(StoreFixture.folder(name))/completion.json"
    if kind == "directory" {
      try fixture.directory.makeDirectory(marker)
    } else {
      try fixture.directory.symlink(marker, to: "run.json")
    }

    #expect(try fixture.problems() == ["\(marker) is corrupt: it is not a regular file"])
  }
}
