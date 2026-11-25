/// What a command that writes files you own answers with once its write is settled
/// (chapter 16 §14).
protocol WriteReporting {
  /// The answer for a person.
  func humanText() -> String

  /// The document of the command's published schema.
  func jsonText() throws(EditReportError) -> String

  /// What a person is told that the document has no field for. With `--json` it goes to the
  /// standard error, which never carries the document.
  var sideNotes: [String] { get }
}

extension WriteReporting {
  var sideNotes: [String] {
    []
  }
}
