import UseCasesCore

/// What `hooks` works through besides the command line.
struct HooksSession {
  /// Names the workspace root without loading the workspace.
  let locator: any WorkspaceRootLocating

  /// Plans what the request does to the clone's hooks.
  let planner: any HookPlanning

  /// Writes the hooks.
  let write: any PlanCarrying

  /// The full path of the `use-cases` that adds the hooks.
  let program: String
}
