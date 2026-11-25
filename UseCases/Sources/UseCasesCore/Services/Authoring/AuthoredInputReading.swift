/// Reads authored input: the use case that `save` takes, a batch for `apply`, a file for
/// `render`, one to search `--like` (chapter 09 §14).
protocol AuthoredInputReading: Sendable {
  /// The value the input holds, held to the rules every use case file is held to: one document,
  /// no tag, no duplicate key, text that would read differently in YAML 1.1 quoted, text never
  /// cut by a comment, and the limits on size.
  ///
  /// YAML and JSON are both read. A file named `.json` is JSON and one named `.yml` or `.yaml`
  /// is YAML. Anything else, the standard input included, is JSON when it reads as JSON, and
  /// YAML otherwise.
  func read(_ source: AuthoredInputSource) throws(AuthoredInputError) -> AuthoredInput
}
