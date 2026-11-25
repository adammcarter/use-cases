import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases hooks` (chapter 18): which git hooks this clone has, and with `add` or `remove`
/// opt-in hooks that run a check at a git moment. It needs the workspace root and git, never the
/// model, so it works on a workspace that does not load.
struct HooksCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Add or remove git hooks for this clone: commit and push.",
  )

  static let name = "hooks"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  // Both are read as words here so that a wrong one is told in the command's own words.
  @Argument(help: "add or remove; leave out to list the hooks.")
  var action: String?

  @Argument(help: "The hooks to add or remove: commit, push.")
  var names: [String] = []

  /// What the command does from `workingDirectory`: the words are read first, then the
  /// workspace root is named, then git is asked, and then the hooks are written.
  ///
  /// - Parameters:
  ///   - session: What the command works through: the root locator, the planner, the writer and
  ///     the `use-cases` that adds the hooks.
  ///   - workingDirectory: Where the command runs.
  func result(
    session: HooksSession,
    workingDirectory: URL,
  ) async -> CommandResult {
    let request: (action: HookAction?, names: [HookName])

    do {
      request = try parsedWords()
    } catch {
      return refusal(.usage, error.message)
    }

    let root: URL

    do {
      root = try session.locator.locateRoot(from: global.start(from: workingDirectory))
    } catch {
      return refusal(error.refusalKind, error.message)
    }

    let plan: HooksPlan

    do {
      plan = try await session.planner.plan(
        HooksRequest(
          root: root,
          action: request.action,
          names: request.names,
          program: session.program,
        ),
      )
    } catch {
      return refusal(.refused, error.message)
    }

    return await carryOut(
      plan,
      action: request.action,
      session: session,
      root: root,
    )
  }

  private func carryOut(
    _ plan: HooksPlan,
    action: HookAction?,
    session: HooksSession,
    root: URL,
  ) async -> CommandResult {
    let outcome: PlannedWriteOutcome

    do {
      outcome = try await session.write.carryOut(
        only: [plan.writes],
        lockingIn: root,
        dryRun: writing.dryRun,
      )
    } catch {
      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    guard outcome != .cancelled else {
      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    return report(
      HooksReport(
        plan: plan,
        action: action,
        notes: outcome == .writtenAfterCancellation
          ? [CommandResult.tooLate("the hooks were written")] : [],
        isDryRun: writing.dryRun,
      ),
      needsAttention: plan.needsAttention,
    )
  }

  private func report(
    _ report: HooksReport,
    needsAttention: Bool,
  ) -> CommandResult {
    let text: String

    do {
      text = try global.json ? report.jsonText() : report.humanText(hint: !global.quiet)
    } catch {
      return .refusal(
        .refused,
        message: "the report could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }

    return needsAttention ? .needsAttention(text) : .done(text)
  }

  private func refusal(
    _ kind: RefusalKind,
    _ message: String,
  ) -> CommandResult {
    .refusal(
      kind,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }
}
