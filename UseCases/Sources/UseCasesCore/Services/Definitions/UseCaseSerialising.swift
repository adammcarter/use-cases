/// Writes a use case as the YAML a definition file holds it as, and `show` prints it as
/// (chapter 16 §14).
protocol UseCaseSerialising: Sendable {
  /// The lines of the use case: its fields in the order people read them, `id` first and
  /// `approved` last, with short lists and small mappings on one line. Reading the text back
  /// through the strict reader gives the same use case.
  ///
  /// - Parameters:
  ///   - definition: The use case.
  ///   - id: What is written under `id`: the full id for a person reading it, or the local id
  ///     a definition file holds.
  func lines(
    of definition: UseCaseDefinition,
    writing id: String,
  ) -> [String]

  /// The same lines as an item of `use_cases` in a definition file, its dash `indent` spaces in:
  /// a dash before the first line, and the others lined up under it. A blank line stays empty,
  /// so the lines of a literal block read back the same.
  func itemLines(
    of definition: UseCaseDefinition,
    writing id: String,
    indent: Int,
  ) -> [String]
}
