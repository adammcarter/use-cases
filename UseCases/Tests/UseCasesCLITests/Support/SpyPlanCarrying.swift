import Foundation
import UseCasesCore
@testable import UseCasesCLI

/// A writer of plans that writes nothing: it notes what it was asked, on a stream, and answers
/// as told.
struct SpyPlanCarrying: PlanCarrying {
  /// One request, as far as a test needs to tell them apart.
  enum Call: Equatable {
    /// A plan of the workspace: the paths it changes, the folders written beside it, whether a
    /// confirmation was asked for, and whether it was a dry run.
    case plan(
      paths: [String],
      alongside: [String],
      confirms: Bool,
      dryRun: Bool,
    )

    /// Plans that are not of the workspace: the folders they are written under, the workspace
    /// whose lock is taken, and whether it was a dry run.
    case only(
      folders: [String],
      lockingIn: String,
      dryRun: Bool,
    )
  }

  /// What it was asked, in order, until ``asked()``.
  let calls: AsyncStream<Call>

  private let noting: AsyncStream<Call>.Continuation
  private let outcome: PlannedWriteOutcome

  init(answering outcome: PlannedWriteOutcome = .written) {
    (calls, noting) = AsyncStream.makeStream(of: Call.self)
    self.outcome = outcome
  }

  /// Every request so far.
  func asked() async -> [Call] {
    noting.finish()

    var found: [Call] = []

    for await call in calls {
      found.append(call)
    }

    return found
  }

  func carryOut(
    _ plan: WritePlan,
    in _: URL,
    alongside others: [FolderWrite],
    confirming: (@Sendable (LoadedWorkspace) -> String?)?,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome {
    noting.yield(
      .plan(
        paths: plan.changes.map(\.path),
        alongside: others.map(\.folder.lastPathComponent),
        confirms: confirming != nil,
        dryRun: dryRun,
      ),
    )

    return outcome
  }

  func carryOut(
    only writes: [FolderWrite],
    lockingIn workspace: URL,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome {
    noting.yield(
      .only(
        folders: writes.map(\.folder.lastPathComponent),
        lockingIn: workspace.lastPathComponent,
        dryRun: dryRun,
      ),
    )

    return outcome
  }
}
