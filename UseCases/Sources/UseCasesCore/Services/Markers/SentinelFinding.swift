/// Finds the marker sentinels in a file's bytes, before anything decodes them (chapter 08
/// "Marker sentinels" and "Text encoding").
protocol SentinelFinding: Sendable {
  /// Whether the bytes hold the sentinel at all. The cheap look every file gets first.
  func holdsSentinel(_ bytes: [UInt8]) -> Bool

  /// Every occurrence of the sentinel, in file order, each with the id the grammar reads after
  /// it. An id is not judged here: it may be empty or malformed.
  func sentinels(
    in bytes: [UInt8],
    lines: LineIndex,
  ) -> [MarkerSentinel]
}
