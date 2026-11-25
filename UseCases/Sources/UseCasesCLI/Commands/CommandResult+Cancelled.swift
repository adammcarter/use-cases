extension CommandResult {
  /// A request the person stopped (Ctrl-C or SIGTERM): exit 130 and one line on stderr
  /// (chapter 16 §6). With `--json` stdout holds the one document every command prints, an error
  /// of kind `cancelled` (chapter 16 §5).
  ///
  /// - Parameters:
  ///   - command: The command that was stopped.
  ///   - json: Whether the request asked for `--json`.
  ///   - message: What happened, when more than the request being stopped needs saying.
  static func cancelled(
    command: String,
    json: Bool,
    message: String = "cancelled",
  ) -> CommandResult {
    var output = ""

    if json {
      let document = RefusalDocument(
        command: command,
        kind: .cancelled,
        message: message,
      )

      // A document that cannot be written leaves stdout empty; the line on stderr still says it.
      output = (try? document.jsonText()).map { text in
        text + "\n"
      } ?? ""
    }

    return CommandResult(
      standardOutput: output,
      standardError: "use-cases \(command): \(message)\n",
      exitCode: 130,
    )
  }

  /// The note beside the normal answer of a command that was cancelled once its write had begun:
  /// the write was finished, and the answer is the one it would have given (chapter 13 §15).
  ///
  /// - Parameter outcome: What the finished write left, in a few words.
  static func tooLate(_ outcome: String) -> String {
    "cancelled too late to stop the write: \(outcome)"
  }
}
