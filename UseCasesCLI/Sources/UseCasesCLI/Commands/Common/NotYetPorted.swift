/// The honest refusal for a command whose Swift port has not landed yet: exit
/// 1 and an error envelope naming the command and the subrow that owns it.
enum NotYetPorted {
  static let code = "cli_not_yet_ported"

  static func output(
    command: String,
    invocation: String,
    subrow: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: code,
        message: "'uc \(invocation)' is not yet ported to the Swift CLI "
          + "(ADR 0007 ladder row \(subrow)).",
      ),
      exitCode: 1,
    )
  }
}
