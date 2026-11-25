extension ScopeSettingsLoadingError {
  /// The reason in one line: the read failure, or the first problem found in the file.
  var summary: String {
    switch self {
    case let .unreadable(error):
      error.description
    case let .invalid(error):
      error.problems.first?.message ?? "it is not valid scope settings"
    }
  }
}
