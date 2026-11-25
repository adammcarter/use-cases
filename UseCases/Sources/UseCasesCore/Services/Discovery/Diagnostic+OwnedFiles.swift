extension Diagnostic {
  /// A file that is the name of one Use Cases owns only when case or Unicode form is ignored
  /// (chapter 09 §19).
  static func ownedFileSpelledDifferently(
    _ found: WorkspacePath,
    expected name: String,
  ) -> Diagnostic {
    Diagnostic(
      error: "owned-file-spelled-differently",
      in: found,
      message: "'\(found)' is not spelled \(name), so it is not read; the file must be named "
        + "exactly \(name), case and Unicode form included",
    )
  }
}
