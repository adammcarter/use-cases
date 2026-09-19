import UseCasesCore

/// The refusal envelope every MCP guard returns (packages/mcp/src/
/// toolHandlers.ts `errorEnvelope`): empty data, not ok, not complete, one
/// error diagnostic.
///
/// It carries no WORKSPACE roots: a refusal happens before, or instead of,
/// resolving one, so `context` reports the server's own working directory —
/// which is exactly what the TypeScript's `process.cwd()` default gives it.
public enum McpErrorEnvelope {
  public static func make(
    command: String,
    code: String,
    message: String,
    environment: McpEnvironment,
  ) -> CliResult {
    CliResult.make(
      command: command,
      data: .object(JSONObject()),
      isSuccessful: false,
      isComplete: false,
      diagnostics: [Diagnostic(code: code, message: message)],
      workspaceRoot: environment.workingDirectory,
      dataRoot: environment.workingDirectory,
    )
  }
}
