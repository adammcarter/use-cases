import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases verify` (chapter 16 §11): gets verdicts from tests. `--start` notes the code and
/// opens a run; the tests then write their reports into it; `--finish` reads them and seals the
/// run; `--abort` closes a run nobody will finish.
struct VerifyCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Get verdicts from tests: --start, your tests, then --finish.",
  )

  static let name = "verify"

  @OptionGroup
  var global: GlobalOptions

  @Flag(
    name: .long,
    help: "Note the code, print the run id and where each report goes; then run your tests.",
  )
  var start = false

  @Flag(
    name: .long,
    help: "Finish a started run: read the reports your tests wrote.",
  )
  var finish = false

  @Flag(
    name: .long,
    help: "--start, the run commands of use-cases-bridge.yml, then --finish.",
  )
  var run = false

  @Flag(
    name: .long,
    help: "Close a started run nobody will finish.",
  )
  var abort = false

  @Option(
    name: .long,
    help: "Read only these validations, separated by commas (--start and --run).",
  )
  var only: String?

  @Option(
    name: [.customLong("run-id")],
    help: "The run to finish or close (--finish and --abort).",
  )
  var runIdentifier: String?

  /// What the command does from `workingDirectory`: the command line is checked first, then the
  /// workspace is loaded and the step runs.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - verifier: The services of the three steps.
  ///   - cancellation: Says whether the request was cancelled, and is told when it writes.
  ///   - workingDirectory: Where the command runs.
  func result(
    loader: any LinkedWorkspaceLoading,
    verifier: Verifier,
    cancellation: any CancellationScoping,
    workingDirectory: URL,
  ) async -> CommandResult {
    let step: VerifyStep

    switch chosenStep() {
    case let .success(found):
      step = found
    case let .failure(refusal):
      return self.refusal(refusal.message)
    }

    let start = global.start(from: workingDirectory)

    // Closing a run needs the store and not the model: a workspace that does not load never
    // keeps a run open (chapter 13 §6).
    guard step != .abort else {
      return await abortResult(
        verifier: verifier,
        start: start,
        cancellation: cancellation,
      )
    }

    let linked: LinkedWorkspace

    do {
      linked = try await loader.load(from: start)
    } catch {
      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    return await perform(
      step,
      in: linked,
      verifier: verifier,
      cancellation: cancellation,
      reloading: LinkedWorkspaceReloader(
        loader: loader,
        start: start,
      ),
    )
  }

  /// Whether the step reports its own cancellation: `--finish` and `--run` seal the run as
  /// interrupted and tell it (chapter 16 §6). The other steps stop before they write, or finish
  /// the write and say the cancellation came too late (chapter 13 §15).
  var reportsOwnCancellation: Bool {
    finish || run
  }

  /// One step, and options that belong to it (chapter 13 §6, chapter 16 §2).
  private func chosenStep() -> Result<VerifyStep, VerifyUsage> {
    let asked = [
      (VerifyStep.start, start),
      (VerifyStep.finish, finish),
      (VerifyStep.run, run),
      (VerifyStep.abort, abort),
    ].filter(\.1).map(\.0)

    guard let step = asked.first else {
      return .failure(.noStep)
    }
    guard asked.count == 1 else {
      return .failure(.severalSteps(asked.map(\.flag)))
    }
    if only != nil, step == .finish || step == .abort {
      return .failure(.onlyBelongsToStart)
    }
    if runIdentifier != nil, step == .start || step == .run {
      return .failure(.runIdentifierBelongsToFinish)
    }

    return .success(step)
  }

  private func perform(
    _ step: VerifyStep,
    in linked: LinkedWorkspace,
    verifier: Verifier,
    cancellation: any CancellationScoping,
    reloading: any WorkspaceReloading,
  ) async -> CommandResult {
    let resolved = ResolvedWorkspace(
      workspace: linked.workspace,
      links: linked.resolution,
    )

    do {
      switch step {
      case .start:
        return try await startResult(
          verifier: verifier,
          in: resolved,
          cancellation: cancellation,
        )
      case .abort:
        // Handled before the workspace is loaded; it never gets here.
        return refusal("verify --abort does not read the workspace")
      case .finish:
        return try await finishResult(
          verifier.finisher.finish(
            VerifyFinishRequest(runIdentifier: runIdentifier),
            in: resolved,
            reloading: reloading,
          ),
          step: .finish,
        )
      case .run:
        return try await finishResult(
          verifier.runner.run(
            VerifyRunRequest(only: onlyValidations),
            in: resolved,
            reloading: reloading,
          ),
          step: .run,
        )
      }
    } catch {
      return refusal(error)
    }
  }

  /// `--only` as a list: the ids between the commas.
  var onlyValidations: [String] {
    guard let only else {
      return []
    }

    return only.split(
      separator: ",",
      omittingEmptySubsequences: false,
    ).map(String.init)
  }

  func refusal(_ error: VerifyError) -> CommandResult {
    guard let kind = error.refusalKind else {
      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    return .refusal(
      kind,
      message: error.message,
      command: Self.name,
      json: global.json,
    )
  }

  func refusal(_ message: String) -> CommandResult {
    .refusal(
      .usage,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }

  func jsonFailure() -> CommandResult {
    .refusal(
      .refused,
      message: "the verify document could not be written as JSON",
      command: Self.name,
      json: true,
    )
  }
}
