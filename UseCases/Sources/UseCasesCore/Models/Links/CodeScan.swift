/// What walking the code found: the marker regions, with the file each is in, and every problem
/// met on the way.
struct CodeScan: Equatable, Sendable {
  /// Every well-paired region of every file, in no particular order.
  var regions: [FileRegion]
  var diagnostics: [Diagnostic]

  /// A scan that has found nothing yet.
  static let empty = CodeScan(
    regions: [],
    diagnostics: [],
  )
}
