import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases init` (chapter 17): sets up a folder as a workspace, from nothing to a first
/// `use-cases status`. It writes base files only, never a test command, never over a file that is
/// there, and plans everything before it writes anything.
struct InitCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Set up a repository: a workspace, an example, a group and a bridge template.",
  )

  static let name = "init"

  @OptionGroup
  var global: GlobalOptions

  @OptionGroup
  var writing: DryRunOptions

  @Flag(
    name: .long,
    help: "Write the workspace file alone.",
  )
  var minimal = false

  @Option(
    name: .long,
    help: "A root prefix for every use case id (chapter 05). Choose it once.",
  )
  var prefix: String?

  @Option(
    name: .long,
    help: "Also add git hooks: commit, push, or commit,push.",
  )
  var hooks: String?

  @Flag(
    name: .long,
    help: "Ask nothing: flags and defaults decide.",
  )
  var noInput = false

  /// Whether a person is asked what the flags did not say: at a terminal, with no `--json` and no
  /// `--no-input`. Such a command is not stopped as a whole, because a person at a prompt must
  /// still be able to stop it with Ctrl-C (chapter 16 §12).
  func asksQuestions(isTerminal: Bool) -> Bool {
    isTerminal && !global.json && !noInput
  }

  /// What the command does from `workingDirectory`: every refusal first, in the order a person
  /// fixes them, then the questions, and then the files and the hooks are written.
  ///
  /// - Parameters:
  ///   - session: What the command works through: the planners, the person at the terminal and
  ///     the writer.
  ///   - workingDirectory: Where the command runs: the folder to set up unless `--workspace`
  ///     names one.
  func result(
    session: InitSession,
    workingDirectory: URL,
  ) async -> CommandResult {
    let named: [HookName]?

    do {
      named = try hooksNamed()
    } catch {
      return refusal(
        .usage,
        error.message,
      )
    }

    let folder = global.folder(from: workingDirectory)
    var setup = InitSetup(
      form: minimal ? .minimal : .full,
      prefix: prefix,
      hooks: named,
    )
    var plan: InitPlan

    do {
      plan = try session.initializer.plan(setup.request(in: folder))
    } catch {
      return refusal(error)
    }

    // Every refusal is above the questions, the hooks included: git is asked about the hooks the
    // flags name before the first question, so a request that cannot be done is never asked.
    var hooks: InitHooks

    do {
      hooks = try await InitHooks.adding(
        named,
        at: plan.root,
        using: session.hooks,
        program: session.program,
      )
    } catch {
      return refusal(
        .refused,
        error.message,
      )
    }

    if asksQuestions(isTerminal: session.isTerminal), let refusal = await ask(
      session: session,
      folder: folder,
      setup: &setup,
      plan: &plan,
      hooks: &hooks,
    ) {
      return refusal
    }

    return await carryOut(
      plan,
      hooks: hooks,
      session: session,
    )
  }

  /// A name that is not a hook is a usage error.
  private func hooksNamed() throws(InitHooksFlagError) -> [HookName]? {
    guard let hooks else {
      return nil
    }

    let words = hooks.split(
      separator: ",",
      omittingEmptySubsequences: false,
    ).map(String.init)

    let known = words.compactMap(HookName.init(rawValue:))

    guard known.count == words.count else {
      throw .notHooks(hooks)
    }

    return HookName.allCases.filter { hook in
      known.contains(hook)
    }
  }

  private func carryOut(
    _ plan: InitPlan,
    hooks: InitHooks,
    session: InitSession,
  ) async -> CommandResult {
    // A command that asked has not held the signals so far: they are held for the write.
    let holdsSignals = asksQuestions(isTerminal: session.isTerminal)

    if holdsSignals {
      await session.cancellation.begin()
    }

    let outcome: PlannedWriteOutcome

    do {
      outcome = try await session.write.carryOut(
        plan.writes,
        in: plan.root,
        alongside: hooks.writes,
        confirming: nil,
        dryRun: writing.dryRun,
      )
    } catch {
      if holdsSignals {
        await session.cancellation.end()
      }

      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    if holdsSignals {
      await session.cancellation.end()
    }

    guard outcome != .cancelled else {
      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    let report = InitReport(
      plan: plan,
      hooks: hooks.added,
      notes: hooks.notes
        + (outcome == .writtenAfterCancellation
          ? [CommandResult.tooLate("the files were written")] : []),
      isDryRun: writing.dryRun,
    )

    return self.report(
      report,
      needsAttention: hooks.needsAttention,
    )
  }

  private func report(
    _ report: InitReport,
    needsAttention: Bool,
  ) -> CommandResult {
    let text: String

    do {
      text = try global.json ? report.jsonText() : report.humanText(hint: !global.quiet)
    } catch {
      return refusal(
        .refused,
        "the report could not be written as JSON",
      )
    }

    return needsAttention ? .needsAttention(text) : .done(text)
  }

  func refusal(
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

  func refusal(_ error: InitError) -> CommandResult {
    refusal(
      error.refusalKind,
      error.message,
    )
  }
}
