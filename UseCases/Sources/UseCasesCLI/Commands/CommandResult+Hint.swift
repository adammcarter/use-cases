extension CommandResult {
  /// The same result with one hint line last on stderr (chapter 16 §18), `→ <command>` and then
  /// what it is for.
  func addingHint(
    _ command: String,
    reason: String? = nil,
  ) -> CommandResult {
    var line = "→ \(command)"

    if let reason {
      line += "   \(reason)"
    }

    return CommandResult(
      standardOutput: standardOutput,
      standardError: standardError + line + "\n",
      exitCode: exitCode,
    )
  }
}
