/// Reads the batch `apply` is sent (chapter 16 §14).
protocol UseCaseBatchReading: Sendable {
  /// The batch the input holds.
  ///
  /// - Parameter argument: What `--file` names: a YAML or JSON file, or `-` for the standard
  ///   input.
  /// - Throws: ``UseCaseBatchError`` when the input cannot be read, is not a mapping of
  ///   `remove` and `save` with something in it, or holds a use case that breaks a rule every
  ///   use case file is held to.
  func read(_ argument: String) throws(UseCaseBatchError) -> UseCaseBatch

  /// The batch an input that is already read holds, which is how a standard input that can be
  /// read once serves two readers.
  ///
  /// - Parameter input: The authored input, as ``AuthoredInputReading`` read it.
  /// - Throws: ``UseCaseBatchError`` as ``read(_:)`` does, but for the input being unreadable.
  func batch(from input: AuthoredInput) throws(UseCaseBatchError) -> UseCaseBatch
}
