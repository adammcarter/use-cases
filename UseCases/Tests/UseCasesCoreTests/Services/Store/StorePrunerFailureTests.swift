import Foundation
import Testing
@testable import UseCasesCore

/// What prune says when the file system refuses it: a run it could not move out of the store is
/// kept; a run moved out whose bytes could not be deleted is gone from the store, and the note
/// names what is left behind.
struct StorePrunerFailureTests {
  /// Moves and deletes as told, or refuses one of the two.
  private struct ScriptedRemover: StoreFolderRemoving {
    let refusesMove: Bool
    let refusesDelete: Bool

    func folderNames(in folder: URL) -> [String] {
      LocalStoreFolderRemover().folderNames(in: folder)
    }

    func exists(_ item: URL) -> Bool {
      LocalStoreFolderRemover().exists(item)
    }

    func move(
      _ folder: URL,
      to destination: URL,
    ) throws(StoreFolderError) {
      guard !refusesMove else {
        throw StoreFolderError(reason: "refused.")
      }

      try LocalStoreFolderRemover().move(
        folder,
        to: destination,
      )
    }

    func delete(_ item: URL) throws(StoreFolderError) {
      guard !refusesDelete || item.lastPathComponent.hasPrefix(".tmp-prune-") == false else {
        throw StoreFolderError(reason: "refused.")
      }

      try LocalStoreFolderRemover().delete(item)
    }
  }

  private let store: StoreFixture
  private static let older = StoreFixture.identifier(1)

  init() throws {
    store = try StoreFixture()
    try store.sealRecord(Self.older)
    try store.sealRecord(StoreFixture.identifier(2))
  }

  private func pruner(_ remover: ScriptedRemover) -> StorePruner {
    StorePruner(
      reading: Result { () throws(StoreSchemaLoadingError) -> any StoreReading in
        try StoreReader()
      },
      measurer: StoreMeasurer(),
      lock: FlockRunLock(),
      remover: remover,
    )
  }

  private func entries() throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      atPath: store.workspace.appendingPathComponent(".use-cases/runs").path,
    ).sorted()
  }

  @Test
  func `a run that cannot be moved out of the store is kept as it was, with a note`() throws {
    let pruner = pruner(ScriptedRemover(refusesMove: true, refusesDelete: false))
    let plan = try pruner.plan(in: store.workspace)
    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )
    let lockFile = store.workspace
      .appendingPathComponent(StoreFixture.folder(Self.older))
      .appendingPathComponent(".lock")

    #expect(outcome.removed.isEmpty)
    #expect(outcome.kept == plan.runs)
    #expect(outcome.notes == ["run \(Self.older) was kept: refused"])
    #expect(try entries().contains(Self.older))
    #expect(!FileManager.default.fileExists(atPath: lockFile.path))
  }

  @Test
  func `a run moved out whose folder cannot be deleted is left over, and its space not freed`(
  ) throws {
    let pruner = pruner(ScriptedRemover(refusesMove: false, refusesDelete: true))
    let plan = try pruner.plan(in: store.workspace)
    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )
    let aside = ".use-cases/runs/.tmp-prune-\(Self.older)"

    #expect(outcome.removed.isEmpty)
    #expect(outcome.leftOver == [PruneLeftover(location: aside, bytes: plan.runs[0].bytes)])
    #expect(
      outcome.notes == [
        "run \(Self.older) is out of the store, but its folder \(aside) could not be deleted "
          + "(refused); the next prune removes it",
      ],
    )
    #expect(try !entries().contains(Self.older))
    #expect(try StoreReader().readHistory(in: store.workspace).runs.count == 1)
    #expect(try StorePruner().plan(in: store.workspace).leftovers.map(\.location) == [aside])
  }

  @Test
  func `a run another prune removed first is passed over without a word`() throws {
    let pruner = StorePruner()
    let plan = try pruner.plan(in: store.workspace)
    try FileManager.default.removeItem(
      at: store.workspace.appendingPathComponent(StoreFixture.folder(Self.older)),
    )

    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(outcome == PruneOutcome(removed: [], notes: []))
  }
}
