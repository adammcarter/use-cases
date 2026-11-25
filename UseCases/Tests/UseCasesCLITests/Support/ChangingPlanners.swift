import Foundation
import UseCasesCore

/// The real saver, after something else has changed the files: what another process does between
/// a command reading a file and handing its change over to be written.
struct ChangingSaver: UseCaseSaving {
  let saver: UseCaseSaver
  let change: @Sendable () -> Void

  func plan(
    savingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange {
    let planned = try saver.plan(
      savingFrom: argument,
      in: workspace,
    )
    change()

    return planned
  }
}

/// The real remover, after something else has changed the files.
struct ChangingRemover: UseCaseRemoving {
  let remover = UseCaseRemover()
  let change: @Sendable () -> Void

  func plan(
    removing identifier: String,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseEditingError) -> UseCaseChange {
    let planned = try remover.plan(
      removing: identifier,
      in: workspace,
      links: links,
    )
    change()

    return planned
  }
}
