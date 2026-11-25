extension YAMLReadingError {
  /// A short, stable name for the kind of refusal.
  var code: DiagnosticCode {
    switch self {
    case .malformed: "not-yaml"
    case .multipleDocuments: "multiple-documents"
    case .tagged: "tagged-value"
    case .undefinedAlias: "undefined-alias"
    case .duplicateKey: "duplicate-key"
    case .unquoted: "unquoted-text"
    case .textCutByComment: "text-cut-by-comment"
    case .leadingByteOrderMark: "leading-byte-order-mark"
    case .unusableKey: "unusable-key"
    case .limitExceeded: "limit-exceeded"
    }
  }

  /// The refusal as a problem in `file`, at the line it points at.
  func diagnostic(in file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      file: file,
      position: try? SourcePosition(line: line),
      code: code,
      severity: .error,
      message: detail,
    )
  }
}
