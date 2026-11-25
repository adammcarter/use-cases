import Foundation
import Testing
@testable import UseCasesCore

/// Two prunes at once: what the other prune takes away while this one works is passed over
/// without a word, never reported as kept or left over (chapter 12 §30). The other prune is played
/// by the lock and the remover below, at set moments, so no timing is involved.
struct StorePrunerRaceTests {
  /// A lock another prune holds: while it is held, the other prune takes the run away.
  private struct HeldByOtherPrune: RunLocking {
    func holding<Value>(
      run _: URL,
      perform _: () async -> Value,
    ) async throws(StoreWritingError) -> Value? {
      nil
    }

    func acquire(run: URL) throws(StoreWritingError) -> HeldRunLock? {
      try? FileManager.default.removeItem(at: run)

      return nil
    }
  }

  /// A remover whose delete of a run moved aside finds the other prune already deleted it.
  private struct DeletedByOtherPrune: StoreFolderRemoving {
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
      try LocalStoreFolderRemover().move(
        folder,
        to: destination,
      )
    }

    func delete(_ item: URL) throws(StoreFolderError) {
      try? FileManager.default.removeItem(at: item)

      throw StoreFolderError(reason: "No such file or directory")
    }
  }

  private let store: StoreFixture

  init() throws {
    store = try StoreFixture()
    try store.sealRecord(StoreFixture.identifier(1))
    try store.sealRecord(StoreFixture.identifier(2))
  }

  private func pruner(
    lock: any RunLocking,
    remover: any StoreFolderRemoving,
  ) -> StorePruner {
    StorePruner(
      reading: Result { () throws(StoreSchemaLoadingError) -> any StoreReading in
        try StoreReader()
      },
      measurer: StoreMeasurer(),
      lock: lock,
      remover: remover,
    )
  }

  @Test
  func `a run the other prune holds and then takes away is not reported kept`() throws {
    let pruner = pruner(
      lock: HeldByOtherPrune(),
      remover: LocalStoreFolderRemover(),
    )
    let plan = try pruner.plan(in: store.workspace)

    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(plan.runs.count == 1)
    #expect(outcome == PruneOutcome(removed: [], notes: []))
  }

  @Test
  func `a run the other prune deleted first is not reported left over`() throws {
    let pruner = pruner(
      lock: FlockRunLock(),
      remover: DeletedByOtherPrune(),
    )
    let plan = try pruner.plan(in: store.workspace)

    let outcome = pruner.remove(
      plan,
      in: store.workspace,
    )

    #expect(plan.runs.count == 1)
    #expect(outcome == PruneOutcome(removed: [], notes: []))
  }

  @Test
  func `a leftover the other prune deleted first is passed over without a word`() throws {
    let leftover = ".use-cases/runs/.tmp-prune-" + StoreFixture.identifier(9)
    try store.write("\(leftover)/run.json", "{}\n")
    let pruner = pruner(
      lock: FlockRunLock(),
      remover: DeletedByOtherPrune(),
    )
    let plan = try pruner.plan(in: store.workspace)

    let outcome = pruner.remove(
      PrunePlan(
        runs: [],
        leftovers: plan.leftovers,
      ),
      in: store.workspace,
    )

    #expect(plan.leftovers.count == 1)
    #expect(outcome == PruneOutcome(removed: [], notes: []))
  }
}
