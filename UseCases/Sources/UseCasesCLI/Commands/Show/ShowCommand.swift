import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases show` (chapter 16 §14): one use case, whole, exactly as `save` takes it. Runs no
/// test and writes nothing.
struct ShowCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "One use case, whole: its full id and every field. Writes nothing.",
  )

  static let name = "show"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "The full id of the use case.")
  var useCase: String

  /// What the command does from `workingDirectory`, reading the workspace through `loader` and
  /// showing the use case through `shower`.
  func result(
    loader: any LinkedWorkspaceLoading,
    shower: any UseCaseShowing,
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

    let shown: ShownUseCase

    do {
      shown = try shower.show(
        useCase,
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

    return report(of: shown)
  }

  private func report(of shown: ShownUseCase) -> CommandResult {
    let report = ShowReport(shown)

    guard global.json else {
      return .done(report.humanText())
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the use case could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }
}
