extension CommandResult {
  /// A command that is done, and something needs the person: the gate is blocked (chapter 16 §6).
  /// Exit 1, nothing on stderr.
  static func needsAttention(_ output: String) -> CommandResult {
    CommandResult(
      standardOutput: output.hasSuffix("\n") ? output : output + "\n",
      standardError: "",
      exitCode: 1,
    )
  }
}
