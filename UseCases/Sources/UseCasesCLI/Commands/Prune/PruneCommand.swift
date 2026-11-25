import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases prune` (chapter 16 §20): removes the sealed runs a later run has said everything
/// again for and that status does not use (chapter 12 §31), so the results store stops growing
/// without bound. A person's command: no agent tool runs it. It judges the workspace as status
/// does, so an INVALID workspace is refused and nothing is removed.
struct PruneCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Remove the runs later runs superseded. Changes no status, gate answer or note.",
  )

  static let name = "prune"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  /// What the command does from `workingDirectory`: the workspace is loaded, the store is read
  /// and planned against the routes as they are now, and then, unless it is a dry run, the planned
  /// runs are removed.
  ///
  /// - Parameters:
  ///   - session: What the command works through.
  ///   - workingDirectory: Where the command runs.
  func result(
    session: PruneSession,
    workingDirectory: URL,
  ) async -> CommandResult {
    let linked: LinkedWorkspace

    do {
      linked = try await session.loader.load(
        from: global.start(from: workingDirectory),
      )
    } catch {
      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    let plan: PrunePlan

    do {
      plan = try session.pruner.plan(
        for: linked.workspace,
        links: linked.resolution,
      )
    } catch {
      return refusal(error.refusalKind, error.message)
    }

    guard !writing.dryRun, !plan.isEmpty else {
      return report(PruneReport(
        removed: plan.runs,
        leftovers: plan.leftovers,
        notes: [],
        isDryRun: writing.dryRun,
      ))
    }

    guard await session.cancellation.claimWrite() else {
      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    let outcome = session.pruner.remove(
      plan,
      from: linked.workspace,
    )

    return report(PruneReport(
      removed: outcome.removed,
      leftovers: outcome.leftovers,
      kept: outcome.kept,
      leftOver: outcome.leftOver,
      notes: outcome.notes,
      isDryRun: false,
    ))
  }

  private func report(_ report: PruneReport) -> CommandResult {
    do {
      return try .done(global.json ? report.jsonText() : report.humanText())
    } catch {
      return refusal(.refused, "the report could not be written as JSON")
    }
  }

  private func refusal(
    _ kind: RefusalKind,
    _ message: String,
  ) -> CommandResult {
    .refusal(
      kind,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }
}
