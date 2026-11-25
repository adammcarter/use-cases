@testable import UseCasesCore

/// Runs no command: `behave` says how each validation's command came out, and sees the run it was
/// asked to run in.
struct MockRunCommandExecutor: RunCommandExecuting {
  let behave: @Sendable (BridgeValidation, OpenRun) async -> CommandExecution

  func execute(
    _ validation: BridgeValidation,
    in run: OpenRun,
  ) async throws(VerifyError) -> CommandExecution {
    await behave(validation, run)
  }
}
