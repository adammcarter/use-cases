import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases apply` (chapter 16 §14, ADR 031): a batch of removals and saves, all of it or none
/// of it, in one fixed order: every removal, then every addition, then every update. It is
/// planned once, checked once as the workspace it would leave, and written once.
struct ApplyCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Apply a batch of removals and saves, all of it or none of it.",
  )

  static let name = "apply"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  @Option(
    name: .long,
    help: "A YAML or JSON file with the batch, or - for the standard input.",
  )
  var file: String

  @Option(
    name: .long,
    help: "Who signed the batch off: each use case it saves is approved as it now reads.",
  )
  var approvedBy: String?

  /// What the command does from `workingDirectory`: the workspace is read, the batch planned,
  /// checked as the workspace would be after it, and written.
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

    let change: UseCaseBatchChange

    do {
      change = try tools.applier.plan(
        applyingFrom: file,
        approvedBy: approvedBy,
        in: linked.workspace,
        links: linked.resolution.links,
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
      ApplyReport(
        change: change,
        notes: notes,
        isDryRun: writing.dryRun,
      )
    }
  }
}
