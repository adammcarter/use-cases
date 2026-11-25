/// What the marker scan found in one file.
///
/// A file with a pairing problem yields no regions: the links in it cannot be read safely
/// (chapter 08 "Pairing"). Its diagnostics still say what is wrong, and a malformed id is
/// reported either way.
struct MarkerScan: Equatable, Sendable {
  /// The well-paired regions, in the order their start sentinels appear in the file.
  let regions: [MarkerRegion]

  /// Every problem, in report order (chapter 09 §27.1): errors for what makes the workspace
  /// INVALID, warnings for the rest.
  let diagnostics: [Diagnostic]

  /// A file with nothing to say.
  static let nothing = MarkerScan(
    regions: [],
    diagnostics: [],
  )
}
