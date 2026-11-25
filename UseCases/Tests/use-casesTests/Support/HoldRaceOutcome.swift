/// What came first in a race between a held test announcing itself and the program saying
/// something.
enum HoldRaceOutcome: Sendable {
  /// The held test announced this value; nil if the hold was given up before it did.
  case held(String?)

  /// The program wrote a line, or its output ended.
  case programSpoke
}
