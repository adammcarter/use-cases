import Foundation
import UseCasesCore

/// Checks and writes the change of `apply` and `approve`, and answers with it.
struct SignOffWriter: SignOffWriting {
  let write: any PlanCarrying

  func answer(
    _ change: PlannedSignOff,
    command: String,
    global: GlobalOptions,
    dryRun: Bool,
    report: ([String]) -> any WriteReporting,
  ) async -> CommandResult {
    let outcome: PlannedWriteOutcome

    do {
      outcome = try await write.carryOut(
        change.writes,
        in: change.root,
        alongside: [],
        confirming: change.divergence,
        dryRun: dryRun,
      )
    } catch {
      return .refusal(
        error,
        command: command,
        json: global.json,
      )
    }

    guard outcome != .cancelled else {
      return .cancelled(
        command: command,
        json: global.json,
      )
    }

    let answer = report(
      outcome == .writtenAfterCancellation
        ? [CommandResult.tooLate("the files were written")] : [],
    )

    guard global.json else {
      return .done(answer.humanText())
    }

    do {
      return try CommandResult(
        standardOutput: CommandResult.done(answer.jsonText()).standardOutput,
        standardError: answer.sideNotes.map { note in
          "warning: \(note)\n"
        }.joined(),
        exitCode: 0,
      )
    } catch {
      return .refusal(
        .refused,
        message: "the answer could not be written as JSON",
        command: command,
        json: true,
      )
    }
  }
}
