import Foundation
import UseCasesCore

/// What `apply` and `approve` are done with: planning their changes to the use cases' lines.
struct SignOffTools {
  let applier: any UseCaseApplying
  let approver: any UseCaseApproving

  /// - Parameters:
  ///   - workingDirectory: Where a relative path given to `--file` is read from.
  ///   - applier: Plans a batch.
  ///   - approver: Plans a sign-off.
  init(
    workingDirectory: URL,
    applier: (any UseCaseApplying)? = nil,
    approver: any UseCaseApproving = UseCaseApprover(),
  ) {
    self.applier = applier ?? UseCaseApplier(workingDirectory: workingDirectory)
    self.approver = approver
  }
}
