import Foundation
import UseCasesCore

/// What `apply` and `approve` plan, as the shared writer needs it: the files to write, the
/// workspace root they are relative to, and what the workspace they leave is held to.
struct PlannedSignOff: Sendable {
  let writes: WritePlan
  let root: URL
  let divergence: @Sendable (LoadedWorkspace) -> String?

  /// The plan of a batch.
  init(_ change: UseCaseBatchChange) {
    writes = change.writes
    root = change.root
    divergence = change.divergence
  }

  /// The plan of a sign-off.
  init(_ change: UseCaseApprovalChange) {
    writes = change.writes
    root = change.root
    divergence = change.divergence
  }
}
