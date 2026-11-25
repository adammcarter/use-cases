import Foundation
import Testing
@testable import UseCasesCore

struct OpenRunFinderTests {
  private let fixture: WriterFixture
  private let finder: OpenRunFinder

  init() throws {
    fixture = try WriterFixture()

    let access = StoreFileAccess(
      fileSystem: LocalFileSystem(),
      json: JSONReader(),
    )

    finder = try OpenRunFinder(
      access: access,
      checker: BundledStoreSchemaLoader().loadChecker(
        for: .start,
        unknownMembers: .ignore,
      ),
    )
  }

  private func open(openedBy: RunOpener = .start) throws -> OpenRun {
    try fixture.writer.openVerifyRun(
      StartDraft.sample(openedBy: openedBy),
      in: fixture.workspace,
    )
  }

  @Test
  func `a store with no runs has no open run`() throws {
    #expect(try finder.openRuns(in: fixture.workspace).open.isEmpty)
  }

  @Test
  func `open verify runs are listed in ascending run id, with who opened them`() throws {
    let first = try open()
    let second = try open(openedBy: .run)

    let found = try finder.openRuns(in: fixture.workspace).open

    #expect(found.map(\.identifier) == [first.identifier, second.identifier])
    #expect(found.map(\.stamp.openedBy) == [.start, .run])
    #expect(found.first?.stamp.selected.map(\.text) == ["auth-tests"])
  }

  @Test
  func `a sealed run is not open`() throws {
    let run = try open()

    _ = try fixture.writer.seal(
      run,
      termination: .interrupted,
    )

    #expect(try finder.openRuns(in: fixture.workspace).open.isEmpty)
    #expect(try finder.find(run.identifier, in: fixture.workspace) == .sealed)
  }

  @Test
  func `an unsealed record run has no stamp, is no verify run, and is found as a record run`()
    throws
  {
    let run = try fixture.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )
    let found = try finder.openRuns(in: fixture.workspace)

    #expect(found.open.isEmpty)
    #expect(found.damaged.isEmpty)
    #expect(found.records == [run.identifier])
    #expect(try finder.find(run.identifier, in: fixture.workspace) == .openRecord(run.identifier))
  }

  @Test
  func `a sealed record run is not open`() throws {
    let run = try fixture.writer.openRun(
      kind: .record,
      in: fixture.workspace,
    )
    _ = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    #expect(try finder.openRuns(in: fixture.workspace).records.isEmpty)
    #expect(try finder.find(run.identifier, in: fixture.workspace) == .sealed)
  }

  @Test
  func `a run id nothing is stored under is missing`() throws {
    #expect(try finder.find(.sample(5), in: fixture.workspace) == .missing)
  }

  private func stampFile(of run: OpenRun) -> URL {
    fixture.directory.location(of: ".use-cases/runs/\(run.identifier.text)/start.json")
  }

  @Test
  func `a stamp that cannot be read is a damaged run, named, and the others are still found`()
    throws
  {
    let broken = try open()
    let fine = try open()

    try Data("not json".utf8).write(to: stampFile(of: broken))

    let found = try finder.openRuns(in: fixture.workspace)
    let damaged = try #require(found.damaged.first)

    #expect(found.open.map(\.identifier) == [fine.identifier])
    #expect(found.damaged.map(\.identifier) == [broken.identifier])
    #expect(damaged.problem.location == ".use-cases/runs/\(broken.identifier.text)/start.json")
    #expect(damaged.canBeClosed)
    #expect(try finder.find(broken.identifier, in: fixture.workspace) == .damaged(damaged))
  }

  @Test
  func `a stamp that breaks its schema is damaged, not skipped`() throws {
    let run = try open()

    try Data(#"{"start_version":1}"#.utf8).write(to: stampFile(of: run))

    let found = try finder.openRuns(in: fixture.workspace)

    #expect(found.open.isEmpty)
    #expect(found.damaged.map(\.identifier) == [run.identifier])
  }

  @Test
  func `a stamp that belongs to another run is damaged`() throws {
    let run = try open()
    let other = try open()
    let stamp = try fixture.read(".use-cases/runs/\(other.identifier.text)/start.json")

    try Data(stamp.utf8).write(to: stampFile(of: run))

    guard case let .damaged(damaged) = try finder.find(run.identifier, in: fixture.workspace)
    else {
      Issue.record("not damaged")
      return
    }

    #expect(damaged.problem.description.contains("is not the run's"))
    #expect(damaged.canBeClosed)
  }

  @Test
  func `a verify run that lost its stamp is damaged, and cannot be closed without one`() throws {
    let run = try open()

    try FileManager.default.removeItem(at: stampFile(of: run))

    guard case let .damaged(damaged) = try finder.find(run.identifier, in: fixture.workspace)
    else {
      Issue.record("not damaged")
      return
    }

    #expect(damaged.problem.location.hasSuffix("/start.json"))
    #expect(!damaged.canBeClosed)
    #expect(damaged.message.contains("cannot be closed"))
  }

  @Test
  func `a run whose manifest cannot be read, without a stamp, is damaged too`() throws {
    let run = try open()

    try FileManager.default.removeItem(at: stampFile(of: run))
    try Data("not json".utf8).write(
      to: fixture.directory.location(of: ".use-cases/runs/\(run.identifier.text)/run.json"),
    )

    guard case let .damaged(damaged) = try finder.find(run.identifier, in: fixture.workspace)
    else {
      Issue.record("not damaged")
      return
    }

    #expect(damaged.problem.location.hasSuffix("/run.json"))
    #expect(!damaged.canBeClosed)
  }

  @Test
  func `a stamp that is a folder is damaged and cannot be closed`() throws {
    let run = try open()
    let stamp = stampFile(of: run)

    try FileManager.default.removeItem(at: stamp)
    try FileManager.default.createDirectory(
      at: stamp,
      withIntermediateDirectories: false,
    )

    guard case let .damaged(damaged) = try finder.find(run.identifier, in: fixture.workspace)
    else {
      Issue.record("not damaged")
      return
    }

    #expect(!damaged.canBeClosed)
  }

  @Test
  func `a folder under runs that is no run id is not looked at`() throws {
    try fixture.directory.makeDirectory(".use-cases/runs/.tmp-0123")
    try fixture.directory.makeDirectory(".use-cases/runs/stray")

    #expect(try finder.openRuns(in: fixture.workspace).open.isEmpty)
  }
}
