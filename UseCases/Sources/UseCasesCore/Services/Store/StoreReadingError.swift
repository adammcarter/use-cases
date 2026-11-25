/// Why the store could not be read (chapter 12 §24).
enum StoreReadingError: Error, Equatable, Sendable {
  /// Everything that is wrong with the store, sorted. A corrupt or unsupported sealed run is
  /// never skipped as though it did not exist, so one problem refuses the whole read.
  case damaged([StoreProblem])
}
