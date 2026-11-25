import UseCasesCore

/// Why `record --interactive` stopped asking.
enum RecordInterviewError: Error, Equatable {
  /// The input ended before every value was given.
  case inputEnded

  /// An answer was refused, or there was nothing to ask about.
  case recording(RecordingError)
}
