/// Chooses the id of a new run (chapter 12 §8).
protocol RunIdentifierAllocating: Sendable {
  /// The id for a run allocated now: the greater of the clock's time with 80 random bits and the
  /// number above `highest`. It is greater than every id in the store, so ids only go up even
  /// when the clock goes back.
  ///
  /// - Parameter highest: The greatest id the store has seen: its high-water mark or its
  ///   greatest run folder. `nil` for a store with neither.
  /// - Throws: ``StoreWritingError/identifiersExhausted`` when nothing is greater than `highest`.
  func next(above highest: RunNumber?) throws(StoreWritingError) -> RunNumber
}
