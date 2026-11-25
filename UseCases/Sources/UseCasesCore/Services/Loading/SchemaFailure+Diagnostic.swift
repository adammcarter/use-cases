extension SchemaFailure {
  /// The failure as a problem in `file`. The value read from a file carries no lines, so the
  /// message says where in the file it is (`... at use_cases/0/title`).
  func diagnostic(in file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      error: DiagnosticCode("schema-\(keyword.rawValue)"),
      in: file,
      message: description,
    )
  }
}
