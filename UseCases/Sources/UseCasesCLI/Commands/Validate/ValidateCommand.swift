import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases validate` (chapter 16 §8): loads the workspace exactly as every command does, runs
/// its link transformers, resolves its links, and reports what it found. Runs no test and writes
/// nothing.
struct ValidateCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Are the authored files right? Runs no test and writes nothing.",
  )

  static let name = "validate"

  @OptionGroup
  var global: GlobalOptions

  /// What the command does from `workingDirectory`, loading through `loader`.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - workingDirectory: Where the command runs.
  func result(
    loader: any LinkedWorkspaceLoading,
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

    return report(of: linked)
  }

  private func report(of linked: LinkedWorkspace) -> CommandResult {
    let report = ValidateReport(
      summary: linked.workspace.summary,
      linkCount: linked.resolution.links.count,
      warnings: linked.resolution.warningLines(including: linked.workspace),
    )

    guard global.json else {
      return .done(report.humanText(hint: !global.quiet))
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the report could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }
}
