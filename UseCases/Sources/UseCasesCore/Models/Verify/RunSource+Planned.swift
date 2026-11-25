extension RunSource {
  /// The source a run plans for a validation (chapter 12 §11): what is known before anything is
  /// read. A started run keeps these until it is finished.
  static func planned(for validation: BridgeValidation) -> RunSource {
    RunSource(
      identifier: validation.identifier,
      report: ReportPaths(validation: validation).relative,
      transformer: validation.transformer.name,
      workingDirectory: validation.workingDirectory.flatMap { $0.isRoot ? nil : $0 },
      command: nil,
      exitCode: nil,
      seconds: nil,
      error: nil,
      diagnostics: [],
    )
  }
}
