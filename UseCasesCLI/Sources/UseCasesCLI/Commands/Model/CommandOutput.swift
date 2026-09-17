import UseCasesCore

/// What a handler returns: the value to render and the process exit code.
///
/// The value is usually a result envelope, but it is rendered as given, so a
/// command may return any JSON value.
struct CommandOutput: Sendable, Equatable {
  let envelope: JSONValue
  let exitCode: Int32

  init(
    envelope: JSONValue,
    exitCode: Int32,
  ) {
    self.envelope = envelope
    self.exitCode = exitCode
  }

  init(
    result: CliResult,
    exitCode: Int32,
  ) {
    envelope = result.jsonValue()
    self.exitCode = exitCode
  }
}
