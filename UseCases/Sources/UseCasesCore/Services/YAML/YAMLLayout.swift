/// How wide a line of authored YAML may get before a list or mapping written on one line is
/// written as a block instead.
struct YAMLLayout: Equatable, Sendable {
  /// A use case as a definition file holds it: items of `use_cases` at two spaces, their fields
  /// at four. Lines are measured from there, so a use case is laid out the same wherever it is
  /// printed.
  static let useCaseFile = YAMLLayout(
    width: 100,
    column: 4,
  )

  /// The most characters (Unicode scalars) a line may have, counted from the left edge of the
  /// file. A text is never wrapped: one longer than this stays on its line.
  let width: Int

  /// The column the text being laid out starts at in the file.
  let column: Int

  /// Whether a line written at the left edge of the text still fits the width in the file.
  func fits(_ line: String) -> Bool {
    column + line.unicodeScalars.count <= width
  }
}
