/// Finds what a valid bridge file does that is worth saying (chapter 10 §18).
protocol BridgeSettingsAdvising: Sendable {
  /// - Parameters:
  ///   - settings: The settings of a file that is valid.
  ///   - writesValidations: Whether the file writes `validations` at all, empty or not.
  ///   - file: The bridge file, which every warning names.
  func warnings(
    for settings: BridgeSettings,
    writesValidations: Bool,
    in file: WorkspacePath,
  ) -> [Diagnostic]
}
