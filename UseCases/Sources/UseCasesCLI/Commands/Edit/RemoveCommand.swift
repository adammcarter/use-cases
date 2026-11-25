import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases remove` (chapter 16 §14): one use case taken out. Its verdicts stay in the store,
/// and the markers that still name it are listed.
struct RemoveCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Take one use case out.",
  )

  static let name = "remove"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  @Argument(help: "The full id of the use case.")
  var useCase: String

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
      change = try tools.remover.plan(
        removing: useCase,
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
      change,
      command: Self.name,
      global: global,
      dryRun: writing.dryRun,
    )
  }
}
