/// What every `--json` document carries (chapter 16 §5).
enum OutputDocument {
  /// The shape version of every `--json` document; it changes only for a shape older
  /// readers cannot read.
  static let version = 1
}
