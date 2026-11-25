import Foundation
import UseCasesCore

/// The one way a command writes files you own (`docs/architecture.md`
/// §2): plan, check, write. The check loads the workspace as the plan would leave it, through a
/// view of the real files with the plan laid over them, as every command loads one; a workspace
/// that would be INVALID is refused and nothing is written. Nothing is copied or written during
/// the check, and `--dry-run` stops there, so a preview can never differ from the real run.
struct PlannedWrite: PlanCarrying {
  private let viewer: any PlanViewing
  private let writer: any PlanWriting
  private let transformers: any TransformerLinkProviding
  private let cancellation: any CancellationScoping
  private let recorder: any PlanRecording

  /// - Parameters:
  ///   - viewer: Shows the workspace as the plan would leave it.
  ///   - writer: Applies the plans, all or nothing.
  ///   - transformers: Runs the link transformers, in the real folder as `validate` runs them,
  ///     sent the use cases as the plan leaves them.
  ///   - cancellation: Told when the write begins: a request cancelled before that writes
  ///     nothing, and one cancelled after finishes the write (chapter 13 §15).
  ///   - recorder: Notes what the files a plan replaces or deletes hold when the plan is handed
  ///     over, for the changes whose planner did not, so the writer can refuse a file changed
  ///     since.
  init(
    viewer: any PlanViewing,
    writer: any PlanWriting,
    transformers: any TransformerLinkProviding,
    cancellation: any CancellationScoping,
    recorder: any PlanRecording = PlanRecorder(),
  ) {
    self.recorder = recorder
    self.viewer = viewer
    self.writer = writer
    self.transformers = transformers
    self.cancellation = cancellation
  }

  /// A change that edits files by their lines uses `confirming` to be sure it changed what it
  /// meant to.
  func carryOut(
    _ plan: WritePlan,
    in root: URL,
    alongside others: [FolderWrite] = [],
    confirming: (@Sendable (LoadedWorkspace) -> String?)? = nil,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome {
    let writes = recorder.recording([FolderWrite(folder: root, plan: plan)] + others)

    try await check(
      plan,
      in: root,
      confirming: confirming,
    )

    return try await write(
      writes,
      lockingIn: root,
      dryRun: dryRun,
    )
  }

  /// Plans that are not of the workspace change no file the workspace holds, so they cannot make
  /// it INVALID, and the model is never loaded.
  func carryOut(
    only writes: [FolderWrite],
    lockingIn workspace: URL,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome {
    try await write(
      recorder.recording(writes),
      lockingIn: workspace,
      dryRun: dryRun,
    )
  }

  private func write(
    _ writes: [FolderWrite],
    lockingIn workspace: URL,
    dryRun: Bool,
  ) async throws(PlannedWriteError) -> PlannedWriteOutcome {
    guard !dryRun else {
      return .previewed
    }

    let pending = writes.filter { write in
      !write.plan.isEmpty
    }

    guard !pending.isEmpty else {
      return .written
    }

    guard await cancellation.claimWrite() else {
      return .cancelled
    }

    do {
      try writer.apply(
        pending,
        lockingIn: workspace,
      )
    } catch {
      throw .writing(error)
    }

    return await cancellation.isCancelled() ? .writtenAfterCancellation : .written
  }

  /// The workspace as the plan would leave it, loaded as every command loads one. A plan with
  /// nothing in it is the workspace as it is.
  private func check(
    _ plan: WritePlan,
    in root: URL,
    confirming: (@Sendable (LoadedWorkspace) -> String?)?,
  ) async throws(PlannedWriteError) {
    let view: WorkspaceView

    do {
      view = try viewer.view(
        showing: plan,
        in: root,
      )
    } catch {
      throw .conflicting(error)
    }

    let linked = LinkedWorkspaceLoader(
      loader: view.loader,
      transformers: transformers,
      resolver: view.resolver,
    )

    let loaded: LinkedWorkspace

    do {
      loaded = try await linked.load(from: .workspace(root))
    } catch {
      throw .leavesInvalid(error)
    }

    if let divergence = confirming?(loaded.workspace) {
      throw .diverges(divergence)
    }
  }
}
