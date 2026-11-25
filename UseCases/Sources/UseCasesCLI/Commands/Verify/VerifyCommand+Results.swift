import Foundation
import UseCasesCore

extension VerifyCommand {
  /// Notes the code, and writes the run unless the request was cancelled by then. A cancellation
  /// that comes once the write has begun is told beside the run (chapter 13 §15).
  func startResult(
    verifier: Verifier,
    in resolved: ResolvedWorkspace,
    cancellation: any CancellationScoping,
  ) async throws(VerifyError) -> CommandResult {
    let prepared = try verifier.starter.prepare(
      VerifyStartRequest(only: onlyValidations),
      in: resolved,
    )

    if !prepared.writesNothing {
      guard await cancellation.claimWrite() else {
        throw .cancelled
      }
    }

    var started = try verifier.starter.commit(prepared)

    if started.isStarted, await cancellation.isCancelled() {
      started = StartedVerifyRun(
        runIdentifier: started.runIdentifier,
        selected: started.selected,
        reports: started.reports,
        notes: started.notes + [CommandResult.tooLate("the run was started")],
      )
    }

    return startResult(started)
  }

  func startResult(_ started: StartedVerifyRun) -> CommandResult {
    guard global.json else {
      return .done(VerifyReport.humanText(start: started, hint: !global.quiet))
    }

    do {
      return try .done(VerifyReport.jsonText(start: started))
    } catch {
      return jsonFailure()
    }
  }

  /// Names the root and closes the run, without loading the workspace.
  func abortResult(
    verifier: Verifier,
    start: WorkspaceStart,
    cancellation: any CancellationScoping,
  ) async -> CommandResult {
    let root: URL

    do {
      root = try verifier.locator.locateRoot(from: start)
    } catch {
      return .refusal(
        error.refusalKind,
        message: error.message,
        command: Self.name,
        json: global.json,
      )
    }

    guard await cancellation.claimWrite() else {
      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    do {
      let aborted = try await verifier.aborter.abort(
        VerifyAbortRequest(runIdentifier: runIdentifier),
        in: root,
      )
      let late = await cancellation.isCancelled()

      return abortResult(
        aborted,
        notes: late ? [CommandResult.tooLate("the run was closed")] : [],
      )
    } catch {
      return refusal(error)
    }
  }

  func abortResult(
    _ aborted: AbortedVerifyRun,
    notes: [String] = [],
  ) -> CommandResult {
    guard global.json else {
      return .done(VerifyReport.humanText(abort: aborted, notes: notes))
    }

    do {
      return try .done(VerifyReport.jsonText(abort: aborted, notes: notes))
    } catch {
      return jsonFailure()
    }
  }

  /// A sealed run, told. A run sealed with run errors is exit 1; a cancelled one is exit 130 with
  /// the sealed run still told (chapter 16 §6).
  func finishResult(
    _ verified: VerifiedRun,
    step: VerifyStep,
  ) -> CommandResult {
    let output = global.json
      ? verified.documentText(
        step: step.rawValue,
        outputVersion: OutputDocument.version,
      )
      : VerifyReport.humanText(
        finish: verified,
        hint: !global.quiet,
      )

    if verified.isCancelled {
      return CommandResult(
        standardOutput: output + "\n",
        standardError: "use-cases \(Self.name): cancelled\n",
        exitCode: 130,
      )
    }

    return verified.hasRunErrors ? .needsAttention(output) : .done(output)
  }
}
