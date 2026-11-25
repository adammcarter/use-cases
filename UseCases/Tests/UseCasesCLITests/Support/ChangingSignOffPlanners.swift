import Foundation
import UseCasesCore

/// The real applier, after something else has changed the files: what another process does
/// between a command reading a file and handing its change over to be written.
struct ChangingApplier: UseCaseApplying {
  let applier: UseCaseApplier
  let change: @Sendable () -> Void

  func plan(
    applyingFrom argument: String,
    approvedBy approver: String?,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseBatchError) -> UseCaseBatchChange {
    let planned = try applier.plan(
      applyingFrom: argument,
      approvedBy: approver,
      in: workspace,
      links: links,
    )
    change()

    return planned
  }
}

/// The real approver, after something else has changed the files.
struct ChangingApprover: UseCaseApproving {
  let approver = UseCaseApprover()
  let change: @Sendable () -> Void

  func plan(
    approving identifiers: [String],
    all: Bool,
    by name: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseApprovingError) -> UseCaseApprovalChange {
    let planned = try approver.plan(
      approving: identifiers,
      all: all,
      by: name,
      in: workspace,
    )
    change()

    return planned
  }
}
