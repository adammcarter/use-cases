/// Applies the repository's normalization to bytes before they are hashed (chapter 11 §12 to
/// §18).
protocol ContentNormalizing: Sendable {
  func normalized(_ bytes: [UInt8]) -> [UInt8]

  /// The normalization of text taken a chunk at a time, which gives what ``normalized(_:)`` gives
  /// for all of it. `nil` when no rule is on: bytes are then left as they are.
  func normalizationRun() -> NormalizationRun?
}
