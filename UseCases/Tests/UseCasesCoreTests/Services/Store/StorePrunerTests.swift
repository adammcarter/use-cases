import Foundation
import Testing
@testable import UseCasesCore

/// `prune` on a real store (chapter 12 §30, §31): whole folders only, never an unfinished, held or
/// damaged run, and a plan that reads only.
struct StorePrunerTests {
  private let store: StoreFixture
  private let pruner = StorePruner()

  private static let older = StoreFixture.identifier(1)
  private static let newer = StoreFixture.identifier(2)
  private static let elsewhere = "uc-route-v1-sha256:" + String(repeating: "c", count: 64)

  init() throws {
    store = try StoreFixture()
  }

  private func exists(_ identifier: String) -> Bool {
    FileManager.default.fileExists(
      atPath: store.workspace.appendingPathComponent(StoreFixture.folder(identifier)).path,
    )
  }

  private func runsFolderNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      atPath: store.workspace.appendingPathComponent(".use-cases/runs").path,
    ).sorted()
  }

  @Test
  func `the plan names the superseded run and the size of its folder, and removes nothing`(
  ) throws {
    try store.sealRecord(Self.older)
    try store.sealRecord(
      Self.newer,
      fingerprint: Self.elsewhere,
    )

    let plan = try pruner.plan(in: store.workspace)
    let measured = StoreMeasurer().bytes(
      below: store.workspace.appendingPathComponent(StoreFixture.folder(Self.older)),
    )

    #expect(plan.runs == [PrunableRun(identifier: Self.older, bytes: measured)])
    #expect(measured > 0)
    #expect(exists(Self.older))
    #expect(exists(Self.newer))
  }

  @Test
  func `removing takes the whole folder away and leaves the store readable`() throws {
    try store.sealRecord(Self.older)
    try store.sealRecord(Self.newer)

    let plan = try pruner.plan(in: store.workspace)
    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(outcome.removed == plan.runs)
    #expect(outcome.notes.isEmpty)
    #expect(try runsFolderNames() == [Self.newer])

    let history = try StoreReader().readHistory(in: store.workspace)

    #expect(history.runs.map(\.identifier.text) == [Self.newer])
  }

  @Test
  func `a run that never finished is never planned and never touched`() throws {
    try store.startRun(Self.older)
    try store.sealRecord(Self.newer)
    try store.sealRecord(StoreFixture.identifier(3))

    let plan = try pruner.plan(in: store.workspace)

    #expect(plan.runs.map(\.identifier) == [Self.newer])

    _ = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(exists(Self.older))
  }

  @Test
  func `a run another process holds is kept, with a note`() throws {
    try store.sealRecord(Self.older)
    try store.sealRecord(Self.newer)

    let plan = try pruner.plan(in: store.workspace)
    let held = try #require(
      try FlockRunLock().acquire(
        run: store.workspace.appendingPathComponent(StoreFixture.folder(Self.older)),
      ),
    )
    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )
    held.release()

    #expect(outcome.removed.isEmpty)
    #expect(outcome.notes == ["run \(Self.older) is in use by another process, so it was kept"])
    #expect(exists(Self.older))
  }

  @Test
  func `a damaged store is refused, and nothing is removed`() throws {
    try store.sealRecord(Self.older)
    try store.sealRecord(Self.newer)
    try store.write("\(StoreFixture.folder(Self.newer))/results.jsonl", "{}\n")

    #expect(throws: StorePruningError.self) {
      try pruner.plan(in: store.workspace)
    }
    #expect(exists(Self.older))
  }

  @Test
  func `a folder an interrupted prune left behind is planned and removed, and nothing else`(
  ) throws {
    try store.sealRecord(Self.newer)
    let leftover = ".use-cases/runs/.tmp-prune-\(Self.older)"
    try store.write("\(leftover)/results.jsonl", "half deleted\n")
    try store.write(".use-cases/runs/.tmp-other/run.json", "{}\n")

    let plan = try pruner.plan(in: store.workspace)

    #expect(plan.runs.isEmpty)
    #expect(plan.leftovers == [PruneLeftover(location: leftover, bytes: 13)])

    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(outcome.leftovers == plan.leftovers)
    #expect(outcome.notes.isEmpty)
    #expect(try runsFolderNames() == [".tmp-other", Self.newer])
    #expect(try pruner.plan(in: store.workspace).isEmpty)
  }

  @Test
  func `a store with no runs has nothing to prune`() throws {
    #expect(try pruner.plan(in: store.workspace).runs.isEmpty)
  }
}
