/// What a command did, ready to be written to the terminal: the two streams and the exit code
/// (chapter 16 §6).
struct CommandResult: Equatable {
  /// What goes to stdout, newline included; empty when nothing does.
  let standardOutput: String

  /// What goes to stderr, newline included; empty when nothing does.
  let standardError: String

  let exitCode: Int32

  /// A command that is done: nothing on stderr.
  static func done(_ output: String) -> CommandResult {
    CommandResult(
      standardOutput: output.hasSuffix("\n") ? output : output + "\n",
      standardError: "",
      exitCode: 0,
    )
  }
}
