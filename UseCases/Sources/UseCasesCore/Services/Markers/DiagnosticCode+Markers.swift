extension DiagnosticCode {
  /// A file that holds the sentinel but whose markers cannot be read: not strict UTF-8, or
  /// starting with a UTF-16 or UTF-32 byte-order mark.
  static let unsupportedText: DiagnosticCode = "unsupported-text"

  /// A sentinel whose id is not a marker id.
  static let malformedMarkerIdentifier: DiagnosticCode = "malformed-marker-id"

  /// A start with no end after it.
  static let markerNeverClosed: DiagnosticCode = "marker-never-closed"

  /// An end with no start before it.
  static let markerWithoutStart: DiagnosticCode = "marker-without-start"

  /// Two pairs that overlap without one holding the other.
  static let markersCross: DiagnosticCode = "markers-cross"

  /// A start for a marker that is already open.
  static let markerNestedInItself: DiagnosticCode = "marker-nested-in-itself"

  /// A region with no content, or only blank lines or whitespace.
  static let emptyMarkerRegion: DiagnosticCode = "empty-marker-region"
}
