extension Diagnostic {
  /// An error with no position. The value read from an authored file carries no lines, so a
  /// model's problems name their file and say in words where in it they are.
  init(
    error code: DiagnosticCode,
    in file: WorkspacePath,
    message: String,
  ) {
    self.init(
      file: file,
      position: nil,
      code: code,
      severity: .error,
      message: message,
    )
  }
}

extension Diagnostic {
  /// A warning with no position, for the same reason.
  init(
    warning code: DiagnosticCode,
    in file: WorkspacePath,
    message: String,
  ) {
    self.init(
      file: file,
      position: nil,
      code: code,
      severity: .warning,
      message: message,
    )
  }
}
