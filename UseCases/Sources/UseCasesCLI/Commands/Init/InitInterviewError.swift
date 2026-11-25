/// Why `init` stopped asking.
enum InitInterviewError: Error, Equatable {
  /// The input ended before every question was answered.
  case inputEnded
}
