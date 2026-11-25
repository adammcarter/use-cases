/// The checks on the bridge settings that need more than the schema: unique ids, the folders and
/// programs the file names (chapter 09 §21, chapter 10 §18). Nothing is run.
protocol BridgeSettingsChecking: Sendable {
  /// Every problem the settings have, in the file `file`.
  ///
  /// - Parameters:
  ///   - settings: The settings, read from a file that passed its schema.
  ///   - root: The workspace the folders and programs are looked for in.
  ///   - file: The bridge file, which every problem names.
  func check(
    _ settings: BridgeSettings,
    in root: WorkspaceRoot,
    file: WorkspacePath,
  ) -> [Diagnostic]
}
