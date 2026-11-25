import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases links` (chapter 16 §13): which code each use case is tied to.
struct LinksCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Which code each use case is tied to. Runs no test and writes nothing.",
  )

  static let name = "links"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "A use case, or the start of its id, to list the links of.")
  var target: String?

  /// What the command does from `workingDirectory`, reading the workspace through `loader` and
  /// reading the target through `targeter`.
  func result(
    loader: any LinkedWorkspaceLoading,
    targeter: any UseCaseTargeting,
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

    // The target narrows the links, never the problems and warnings, which come whole.
    var links = linked.resolution.links

    if let target {
      do {
        let named = try targeter.identifiers(
          matching: target,
          in: linked.workspace,
        )

        links = links.filter { link in
          named.contains(link.useCase)
        }
      } catch {
        return .refusal(
          .usage,
          message: error.message,
          command: Self.name,
          json: global.json,
        )
      }
    }

    return report(
      links: links,
      warnings: linked.resolution.warningLines,
    )
  }

  private func report(
    links: [ResolvedLink],
    warnings: [String],
  ) -> CommandResult {
    let report = LinksReport(
      links: links,
      warnings: warnings,
    )

    guard global.json else {
      return .done(report.humanText())
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the links could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }
}
