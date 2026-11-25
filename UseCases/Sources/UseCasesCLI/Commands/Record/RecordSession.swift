import UseCasesCore

/// What `use-cases record` talks to besides the workspace.
struct RecordSession {
  /// Checks the request and writes the run.
  let recorder: any VerdictRecording

  /// Asks the person for each value when `--interactive` is given.
  let prompter: any Prompting

  /// Says whether the request was cancelled, and is told when the command writes.
  let cancellation: any CancellationScoping

  /// Whether a person is at a terminal, which `--interactive` needs.
  let isTerminal: Bool
}
