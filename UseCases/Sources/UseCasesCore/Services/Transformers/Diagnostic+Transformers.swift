/// What a transformer says about itself, filed under the bridge settings that name it.
extension Diagnostic {
  /// A line from a links transformer's `diagnostics`: a warning, whatever it says, because a
  /// transformer's words never decide anything (chapter 10 §13).
  static func transformerSaid(
    _ text: String,
    by name: String,
  ) -> Diagnostic {
    Diagnostic(
      file: WorkspacePath.root.appending(literal: BridgeSettingsLoader.fileName),
      position: nil,
      code: .transformerDiagnostic,
      severity: .warning,
      message: "\(name): \(text)",
    )
  }
}
