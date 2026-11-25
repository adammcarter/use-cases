/// What pairing a file's sentinels gave.
struct MarkerPairingOutcome: Equatable, Sendable {
  /// The pairs that closed, in the order their ends appear.
  let pairs: [MarkerPair]
  let problems: [MarkerPairingProblem]
}
