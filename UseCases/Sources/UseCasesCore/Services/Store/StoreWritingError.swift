/// Why the store could not be written (chapter 12 §9, §18 and §24).
enum StoreWritingError: Error, Equatable, Sendable {
  /// `run-order.json` is malformed or from a newer version. Allocation never silently resets it.
  case allocation(StoreProblem)

  /// Every run id up to the greatest there is has been allocated.
  case identifiersExhausted

  /// The system would not let a file or folder be written.
  case unwritable(
    location: String,
    reason: String,
  )

  /// A document the core was about to write breaks its own schema, so nothing was written.
  case invalidDocument(
    location: String,
    problems: String,
  )

  /// The run already has its completion marker. A sealed run is never changed.
  case sealed(RunIdentifier)

  /// A file of the run being written could not be read back, or is not what it has to be.
  case damaged(StoreProblem)

  /// The failure as one line a person reads.
  var description: String {
    switch self {
    case let .allocation(problem):
      "the run order cannot be used: \(problem)"
    case .identifiersExhausted:
      "no greater run id is left to allocate"
    case let .unwritable(location, reason):
      "\(location) cannot be written: \(reason)"
    case let .invalidDocument(location, problems):
      "\(location) would break its schema (\(problems)), so nothing was written"
    case let .sealed(identifier):
      "run \(identifier) is sealed and cannot change"
    case let .damaged(problem):
      "\(problem)"
    }
  }
}
