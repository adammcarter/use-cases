extension CommandResult {
  /// A refused request (chapter 16 §6): exit 2, the message on stderr as `error: <message>`, and
  /// with `--json` the same message in the document on stdout.
  static func refusal(
    _ kind: RefusalKind,
    message: String,
    command: String?,
    json: Bool,
  ) -> CommandResult {
    let document = RefusalDocument(
      command: command,
      kind: kind,
      message: message,
    )

    var output = ""
    var note = ""

    if json {
      do {
        output = try document.jsonText() + "\n"
      } catch {
        // Still a refusal with its message; stdout stays empty, and stderr says why.
        note = "error: the --json document for this refusal could not be written\n"
      }
    }

    return CommandResult(
      standardOutput: output,
      standardError: "error: \(message)\n" + note,
      exitCode: 2,
    )
  }
}
