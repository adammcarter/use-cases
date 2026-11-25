/// Pairs start and end sentinels by position, first to last, like brackets (chapter 08
/// "Pairing"). It is the same for every language and comes before any use-case lookup.
protocol MarkerPairing: Sendable {
  /// Pairs the sentinels, which are in file order and whose ids are all well formed. Sentinels
  /// with a malformed id take no part, so the caller leaves them out.
  func pair(_ sentinels: [MarkerSentinel]) -> MarkerPairingOutcome
}
