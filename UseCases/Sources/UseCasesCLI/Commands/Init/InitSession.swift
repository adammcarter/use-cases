import UseCasesCore

/// What `init` works through besides the command line.
struct InitSession {
  /// Plans the files.
  let initializer: any WorkspaceInitializing

  /// Plans the hooks.
  let hooks: any HookPlanning

  /// Asks the person at the terminal what the flags did not say.
  let prompter: any Prompting

  /// Checks the plan on a copy of the workspace and writes it.
  let write: any PlanCarrying

  /// Says whether the request was cancelled, and is held for the write when `init` asked
  /// questions, which a person must be able to stop with Ctrl-C.
  let cancellation: any CancellationScoping

  /// The full path of the `use-cases` that adds the hooks.
  let program: String

  /// Whether a person is at a terminal: stdin and stdout.
  let isTerminal: Bool
}
