/// Which end of a region a sentinel marks (chapter 08 "Marker sentinels").
enum MarkerSentinelKind: Hashable, Sendable {
  /// An opening sentinel followed by the marker id.
  case start

  /// The word `end` after the sentinel, then the marker id.
  case end
}
