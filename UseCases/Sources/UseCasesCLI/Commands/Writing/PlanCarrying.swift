import Foundation
import UseCasesCore

/// The one way a command writes files you own: plan, check, write
/// (`docs/architecture.md` §2).
protocol PlanCarrying: Sendable {
  /// Checks the plan and, unless `dryRun`, writes it.
  ///
  /// - Parameters:
  ///   - plan: What to write.
  ///   - root: The workspace root the plan's paths are relative to.
  ///   - others: What is written beside it, outside the workspace, such as the hooks of a git
  ///     clone: the check is of the workspace alone, and these are written after it, under the
  ///     same claim to write.
  ///   - confirming: Asked about the workspace as the plan would leave it: what it says the
  ///     workspace holds that the change did not mean refuses the plan.
  ///   - dryRun: Stop after the check.
  func carryOut(
    _ plan: WritePlan,
    in root: URL,
    alongside others: [FolderWrite],
    confirming: (@Sendable (LoadedWorkspace) -> String?)?,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome

  /// Writes plans that are not of the workspace, which are not checked on a copy of it.
  ///
  /// - Parameters:
  ///   - writes: What to write, each under its own folder.
  ///   - workspace: The workspace root, whose `.use-cases/` folder holds the lock every writer
  ///     takes.
  ///   - dryRun: Write nothing.
  func carryOut(
    only writes: [FolderWrite],
    lockingIn workspace: URL,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome
}
