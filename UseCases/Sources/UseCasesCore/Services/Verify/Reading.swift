/// What reading the selected validations came to.
struct Reading: Equatable, Sendable {
  /// One outcome for each validation read, in the order of the bridge settings. A cancelled read
  /// stops the list.
  let outcomes: [SourceOutcome]

  /// The request was cancelled before every report was read, or before judging began.
  let isCancelled: Bool
}
