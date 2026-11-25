/// What walking the code found: every file the scan reads, in no particular order, and every
/// problem and warning met on the way.
struct CodeWalk: Equatable, Sendable {
  var files: [WalkedFile]
  var diagnostics: [Diagnostic]

  /// A walk that has found nothing yet.
  static let empty = CodeWalk(
    files: [],
    diagnostics: [],
  )
}
