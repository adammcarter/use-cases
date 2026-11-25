/// Builds marker text at run time. The tool scans its own repository for markers, so no source file
/// may spell the sentinel as one literal.
enum MarkerText {
  /// The bytes that open every marker.
  static let sentinel = "@use-case" + ":"
}
