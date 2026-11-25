/// A start sentinel and the end sentinel that closes it.
struct MarkerPair: Hashable, Sendable {
  let start: MarkerSentinel
  let end: MarkerSentinel
}
