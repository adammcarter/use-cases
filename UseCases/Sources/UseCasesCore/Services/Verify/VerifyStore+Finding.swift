import Foundation

extension VerifyStore {
  /// Every unsealed verify run, the damaged ones apart, or the storage error that stopped the
  /// search.
  func allRuns(in workspace: URL) throws(VerifyError) -> OpenRuns {
    do {
      return try finder.openRuns(in: workspace)
    } catch {
      throw .storage(error.description)
    }
  }

  /// Every open verify run. A run whose own files are damaged is refused by name, never skipped
  /// (chapter 13 §6): whoever wanted to choose among the open runs is told which one is wrong.
  func openRuns(in workspace: URL) throws(VerifyError) -> [OpenVerifyRun] {
    let runs = try allRuns(in: workspace)

    if let damaged = runs.damaged.first {
      throw .storage(damaged.message)
    }

    return runs.open
  }

  /// The id of every open run, verify or record, in ascending order. A run whose own files are
  /// damaged is refused by name, as ``openRuns(in:)`` does.
  func openIdentifiers(in workspace: URL) throws(VerifyError) -> [RunIdentifier] {
    let runs = try allRuns(in: workspace)

    if let damaged = runs.damaged.first {
      throw .storage(damaged.message)
    }

    return (runs.open.map(\.identifier) + runs.records).sorted()
  }

  /// How a person sees a run id of this store: every run folder counts, sealed or not, and an
  /// unreadable store counts none.
  func shortener(in workspace: URL) -> RunIdentifierShortener {
    let runs = StoreFile(workspace: workspace).appending(StoreLayout.runsFolder)
    let entries = (try? access.entries(in: runs)) ?? []

    return RunIdentifierShortener(
      runs: entries.compactMap { entry in
        (try? RunIdentifier(validating: entry.name))?.text
      },
    )
  }

  /// What the store holds for the run id the person typed. Text that is no run id names no run.
  func find(
    _ text: String,
    in workspace: URL,
  ) throws(VerifyError) -> FoundRun {
    guard let identifier = try? RunIdentifier(validating: text) else {
      return .missing
    }

    do {
      return try finder.find(
        identifier,
        in: workspace,
      )
    } catch {
      throw .storage(error.description)
    }
  }

  /// The run's folder.
  func folder(
    of run: RunIdentifier,
    in workspace: URL,
  ) -> StoreFile {
    StoreFile(workspace: workspace)
      .appending(StoreLayout.runsFolder)
      .appending(run.text)
  }
}
