extension StatusJudge {
  /// Whether some validation of the bridge settings has a run command, which is what `verify
  /// --run` runs.
  static func hasRunCommand(in workspace: LoadedWorkspace) -> Bool {
    workspace.bridge?.validations.contains { validation in
      validation.run != nil
    } ?? false
  }
}
