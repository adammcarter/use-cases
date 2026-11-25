/// A way the sentinels of a file fail to pair, each one INVALID (chapter 08 "Pairing").
enum MarkerPairingProblem: Hashable, Sendable {
  /// A start with no end after it.
  case neverClosed(MarkerSentinel)

  /// An end with no start before it.
  case withoutStart(MarkerSentinel)

  /// `end` closes `start` while `stillOpen`, started after `start`, has not been closed.
  case crossing(
    end: MarkerSentinel,
    start: MarkerSentinel,
    stillOpen: MarkerSentinel,
  )

  /// A start for a marker that is already open: `outer` is the one it sits inside.
  case nestedInItself(
    MarkerSentinel,
    outer: MarkerSentinel,
  )
}
