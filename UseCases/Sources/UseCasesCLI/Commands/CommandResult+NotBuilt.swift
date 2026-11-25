extension CommandResult {
  /// A designed command this build does not answer yet
  /// (`docs/architecture.md` §6):
  /// exit 3, one line on stderr and nothing on stdout, so that nothing mistakes it for an answer.
  static func notBuiltYet(command: String) -> CommandResult {
    CommandResult(
      standardOutput: "",
      standardError: "use-cases \(command) is not built yet\n",
      exitCode: 3,
    )
  }
}
