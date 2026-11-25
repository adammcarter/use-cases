import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases search` (chapter 16 §15): use cases by words, or by likeness to a whole use case,
/// best first, in pages. Runs no test and writes nothing.
struct SearchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Find use cases by words, or by likeness to one, best first, in pages. "
      + "Writes nothing.",
  )

  static let name = "search"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "Words to look for, \"a phrase\" that must appear, -word to leave out.")
  var words: [String] = []

  @Option(
    name: .long,
    help: "A whole use case instead of words: a file, or - for the standard input.",
  )
  var like: String?

  @Option(
    name: .long,
    help: "Only use cases under this id prefix.",
  )
  var under: String?

  @Option(
    name: .long,
    help: "Only the members of this group.",
  )
  var group: String?

  @Option(
    name: .long,
    help: "Only these value tiers, such as critical,core.",
  )
  var tier: String?

  @Option(
    name: .long,
    help: "Only these states, such as failed,stale. draft is a state here.",
  )
  var state: String?

  @Option(
    name: .customLong("in"),
    help: "Only these fields, such as title,intent. The default is all of them.",
  )
  var fields: String?

  @Flag(
    name: .long,
    help: "Only whole words, exactly as typed: no word starts, no typos.",
  )
  var exact = false

  @Flag(
    name: .long,
    help: "Add each match's whole use case to --json.",
  )
  var full = false

  // A text, not a number, so that a value outside 1 to 100 is refused in this command's words.
  @Option(
    name: .long,
    help: "Matches a page, 1 to 100. The default is 20.",
  )
  var pageSize: String?

  @Option(
    name: .long,
    help: "The token of the next page. Passed alone.",
  )
  var next: String?

  /// What the command does from `workingDirectory`: the request is read first, then the
  /// workspace is loaded and judged, and then the use cases are searched.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - judge: Judges every use case, whose states `--state` and each match tell.
  ///   - tools: Reads what was typed, and finds the matches.
  ///   - workingDirectory: Where the command runs.
  func result(
    loader: any LinkedWorkspaceLoading,
    judge: any StatusJudging,
    tools: SearchTools,
    workingDirectory: URL,
  ) async -> CommandResult {
    let request: SearchRequest

    do {
      request = try self.request()
    } catch {
      return usage(error.message)
    }

    let plan: SearchPlan

    do {
      plan = try tools.planner.plan(request)
    } catch {
      return refusal(error)
    }

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

    let status: WorkspaceStatus

    do {
      status = try judge.judge(
        linked.workspace,
        links: linked.resolution,
      )
    } catch {
      return .refusal(
        error.refusalKind,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    let page: SearchPage

    do {
      page = try tools.searcher.search(
        plan,
        in: linked.workspace,
        status: status,
      )
    } catch {
      return refusal(error)
    }

    return report(of: page)
  }
}
