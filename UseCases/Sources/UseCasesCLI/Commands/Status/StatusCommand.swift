import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases status` (chapter 16 §9, §10): every use case worst first, one use case in detail,
/// and with `--gate` whether anything blocks. Runs no test and writes nothing.
struct StatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Every use case, worst first; one use case in detail; with --gate, does anything "
      + "block? Runs no test and writes nothing.",
  )

  static let name = "status"

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: "A use case, or the start of its id, to show.")
  var target: String?

  @Option(
    name: .long,
    help: "Only the members of this group.",
  )
  var group: String?

  // A text, not an enum, so that a word that is no state is refused in this command's own words.
  @Option(
    name: .long,
    help: "Only these states, such as failed,stale. draft is a state here.",
  )
  var state: String?

  @Flag(
    name: .long,
    help: "Does anything block? Exits 1 when it does.",
  )
  var gate = false

  @Flag(
    name: .long,
    help: "With --gate: incomplete and unverified use cases block too.",
  )
  var strict = false

  /// What the command does from `workingDirectory`: the request is checked first, then the
  /// workspace is loaded and judged.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - judge: Judges every use case against the results store.
  ///   - targeter: Reads the use case or id prefix the command line names.
  ///   - groupSelector: Reads the group the command line names.
  ///   - workingDirectory: Where the command runs.
  func result(
    loader: any LinkedWorkspaceLoading,
    judge: any StatusJudging,
    targeter: any UseCaseTargeting,
    groupSelector: any GroupSelecting,
    workingDirectory: URL,
  ) async -> CommandResult {
    let filter: StatusStateFilter?

    do {
      filter = try requestedStates()
    } catch {
      return usage(error.message)
    }

    if let refusal = combinationRefusal() {
      return usage(refusal)
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

    var named: Set<String>?

    if let target {
      do {
        named = try targeter.identifiers(
          matching: target,
          in: linked.workspace,
        )
      } catch {
        return usage(error.message)
      }
    }

    var members: Set<String>?

    if let group {
      do {
        members = try groupSelector.members(
          ofGroup: group,
          in: linked.workspace,
        )
      } catch {
        return usage(error.message)
      }
    }

    return judged(
      linked,
      by: judge,
      named: named,
      members: members,
      filter: filter,
    )
  }

  /// The last step: the workspace is judged, and what is judged is reported.
  private func judged(
    _ linked: LinkedWorkspace,
    by judge: any StatusJudging,
    named: Set<String>?,
    members: Set<String>?,
    filter: StatusStateFilter?,
  ) -> CommandResult {
    let status: WorkspaceStatus

    do {
      status = try judge.judge(
        linked.workspace,
        links: linked.resolution,
        measuringStore: showsStore(named: named),
      )
    } catch {
      return .refusal(
        error.refusalKind,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    return report(
      of: status,
      named: named,
      members: members,
      filter: filter,
    )
  }

  /// Whether the view asked for shows the store's line (chapter 16 §9): the list, the one-line
  /// view and the JSON document, never the gate or one use case in detail.
  private func showsStore(named: Set<String>?) -> Bool {
    guard !gate else {
      return false
    }

    return global.json || !(named?.count == 1 && named?.first == target)
  }

  private func requestedStates() throws(StatusStateFilterError) -> StatusStateFilter? {
    guard let state else {
      return nil
    }

    return try StatusStateFilter(parsing: state)
  }

  /// What `--strict` and `--gate` cannot be done with; `nil` when the line is fine.
  private func combinationRefusal() -> String? {
    if strict, !gate {
      return "--strict belongs with --gate"
    }

    if gate, state != nil || target != nil {
      return "--gate cannot be combined with --state or a use case: it considers every use "
        + "case in its scope"
    }

    return nil
  }

  private func usage(_ message: String) -> CommandResult {
    .refusal(
      .usage,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }
}
