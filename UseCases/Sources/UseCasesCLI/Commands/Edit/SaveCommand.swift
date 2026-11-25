import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases save` (chapter 16 §14): one use case created or replaced whole, from a YAML or JSON
/// file or the standard input. Only that use case's lines change, and nothing that would leave
/// the workspace INVALID is ever written.
struct SaveCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Create or replace one use case, whole.",
  )

  static let name = "save"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  @Option(
    name: .long,
    help: "A YAML or JSON file with the use case, or - for the standard input.",
  )
  var file: String

  /// What the command does from `workingDirectory`: the workspace is read, the change planned,
  /// checked as the workspace would be after it, and written.
  func result(
    loader: any LinkedWorkspaceLoading,
    tools: EditTools,
    writer: EditWriter,
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

    let change: UseCaseChange

    do {
      change = try tools.saver.plan(
        savingFrom: file,
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
      change,
      command: Self.name,
      global: global,
      dryRun: writing.dryRun,
    )
  }
}
