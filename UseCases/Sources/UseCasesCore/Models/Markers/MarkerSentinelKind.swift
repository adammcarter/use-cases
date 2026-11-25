/// Which end of a region a sentinel marks (chapter 08 "Marker sentinels").
enum MarkerSentinelKind: Hashable, Sendable {
  /// `@use-case:<marker-id>`.
  case start

  /// `@use-case:end <marker-id>`.
  case end
}
