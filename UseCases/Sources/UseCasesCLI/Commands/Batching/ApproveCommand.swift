import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases approve` (chapter 16 §14, ADR 032): the promise of each use case approved as it
/// reads now, recorded on the use case itself with the name, today's date and a fingerprint of
/// the promise.
struct ApproveCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Record a sign-off of each use case's promise as it reads now.",
  )

  static let name = "approve"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  @Argument(help: "The full ids of the use cases to sign off; or --all.")
  var useCases: [String] = []

  @Flag(
    name: .long,
    help: "Every use case in the workspace, drafts included.",
  )
  var all = false

  @Option(
    name: .customLong("by"),
    help: "Who signed off.",
  )
  var approver: String

  /// What the command does from `workingDirectory`: the workspace is read, the sign-off
  /// planned, checked as the workspace would be after it, and written.
  func result(
    loader: any LinkedWorkspaceLoading,
    tools: SignOffTools,
    writer: any SignOffWriting,
    workingDirectory: URL,
  ) async -> CommandResult {
    let linked: LinkedWorkspace

    do {
      linked = try await loader.load(
        from: global.start(from: workingDirectory),
      )
    } catch {
      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    let change: UseCaseApprovalChange

    do {
      change = try tools.approver.plan(
        approving: useCases,
        all: all,
        by: approver,
        in: linked.workspace,
      )
    } catch {
      return .refusal(
        error.refusalKind,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    return await writer.answer(
      PlannedSignOff(change),
      command: Self.name,
      global: global,
      dryRun: writing.dryRun,
    ) { notes in
      ApproveReport(
        change: change,
        notes: notes,
        isDryRun: writing.dryRun,
      )
    }
  }
}
