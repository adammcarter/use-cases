import UseCasesCore

/// Checks and writes the change of `save` and `remove`, and answers with it.
struct EditWriter {
  let write: any PlanCarrying

  /// Checks the change as the workspace would be after it and, unless `dryRun`, writes it.
  ///
  /// - Parameters:
  ///   - change: What `save` or `remove` planned.
  ///   - command: `save` or `remove`.
  ///   - global: The options every command takes.
  ///   - dryRun: Stop after the check.
  func answer(
    _ change: UseCaseChange,
    command: String,
    global: GlobalOptions,
    dryRun: Bool,
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

    let report = EditReport(
      command: command,
      change: change,
      notes: outcome == .writtenAfterCancellation
        ? [CommandResult.tooLate("the files were written")] : [],
      isDryRun: dryRun,
    )

    guard global.json else {
      return .done(report.humanText(hint: !global.quiet))
    }

    do {
      return try .done(report.jsonText())
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
