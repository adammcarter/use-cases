/// What pairing has seen so far: the starts still waiting for an end, and what it has found.
struct PairingState {
  /// The starts not yet closed, innermost last.
  var open: [MarkerSentinel] = []

  /// How many starts are open for each id.
  var openCounts: [String: Int] = [:]
  var pairs: [MarkerPair] = []
  var problems: [MarkerPairingProblem] = []
}
