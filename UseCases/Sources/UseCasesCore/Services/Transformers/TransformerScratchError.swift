/// Why a transformer's private folder could not be made or written.
enum TransformerScratchError: Error, Equatable, Sendable {
  case unavailable(reason: String)
}
