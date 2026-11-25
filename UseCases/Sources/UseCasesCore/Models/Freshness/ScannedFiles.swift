/// The files the code scan reads (chapter 09 §20.3), which a resource glob may match.
struct ScannedFiles: Equatable, Sendable {
  /// Sorted by path, each once. A symlink is a file here: it is read as its target text.
  var files: [WorkspacePath]
  var diagnostics: [Diagnostic]

  /// No file seen yet.
  static let empty = ScannedFiles(
    files: [],
    diagnostics: [],
  )
}
