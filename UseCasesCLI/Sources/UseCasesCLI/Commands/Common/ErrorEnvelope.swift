import UseCasesCore

/// The standard failure envelope (packages/cli/src/runtime.ts `errorEnvelope`):
/// empty data, not ok, not complete, one error diagnostic.
enum ErrorEnvelope {
  static func make(
    command: String,
    code: String,
    message: String,
  ) -> CliResult {
    CliResult.make(
      command: command,
      data: .object(JSONObject()),
      isSuccessful: false,
      isComplete: false,
      diagnostics: [Diagnostic(code: code, message: message)],
    )
  }
}
