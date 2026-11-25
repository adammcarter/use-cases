import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases render` (chapter 21 §7, ADR 033): one of the four layouts people read, drawn by the
/// core from what the agent sends and what the workspace holds. Writes nothing; a results layout
/// whose gate is blocked is still an answer, exit 0. An intent comes before any use case, so it
/// reads no workspace, unless `--workspace` names one: then it is refused when that one is not a
/// workspace, as every command is.
struct RenderCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Draw a layout people read: intent, brief, proposal or results. Writes nothing.",
  )

  static let name = "render"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "The layout: intent, brief, proposal or results.")
  var kind: RenderKind

  @Option(
    name: .long,
    help: "A YAML or JSON file with the intent or the proposal, or - for the standard input.",
  )
  var file: String

  /// What the command does from `workingDirectory`. An intent comes before any use case, so it
  /// never reads a workspace; every other layout does.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - tools: Draws the layouts.
  ///   - style: How the headers are set for a person; a `--json` document is always plain.
  ///   - workingDirectory: Where the command runs.
  func result(
    loader: any LinkedWorkspaceLoading,
    tools: RenderTools,
    style: LayoutStyle,
    workingDirectory: URL,
  ) async -> CommandResult {
    let layout: RenderedLayout

    if kind == .intent {
      if global.workspace != nil {
        do {
          _ = try await loader.load(
            from: global.start(from: workingDirectory),
          )
        } catch {
          return .refusal(
            error,
            command: Self.name,
            json: global.json,
          )
        }
      }

      do {
        layout = try .intent(tools.intents.intent(readingFrom: file))
      } catch {
        return refusal(error)
      }
    } else {
      // The layouts that come after the use cases need the workspace as it is.
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

      do {
        layout = try drawn(
          from: linked,
          with: tools,
        )
      } catch {
        return refusal(error)
      }
    }

    return report(
      of: layout,
      style: style,
    )
  }

  private func drawn(
    from linked: LinkedWorkspace,
    with tools: RenderTools,
  ) throws(LayoutRenderingError) -> RenderedLayout {
    switch kind {
    case .intent:
      try .intent(tools.intents.intent(readingFrom: file))
    case .brief:
      try .brief(
        tools.briefs.brief(
          readingFrom: file,
          in: linked.workspace,
        ),
      )
    case .proposal:
      try .proposal(
        tools.proposals.proposal(
          readingFrom: file,
          in: linked.workspace,
        ),
      )
    case .results:
      try .results(
        tools.results.results(
          readingFrom: file,
          in: linked.workspace,
          links: linked.resolution,
        ),
      )
    }
  }

  private func refusal(_ error: LayoutRenderingError) -> CommandResult {
    .refusal(
      error.refusalKind,
      message: error.message,
      command: Self.name,
      json: global.json,
    )
  }

  private func report(
    of layout: RenderedLayout,
    style: LayoutStyle,
  ) -> CommandResult {
    let report = RenderReport(
      layout: layout,
      style: style,
    )

    guard global.json else {
      return .done(report.humanText())
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the layout could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }
}
