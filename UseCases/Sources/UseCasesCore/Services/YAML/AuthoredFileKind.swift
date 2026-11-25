/// Which kind of authored file is being read; the comment rule (chapter 09 §14) depends on it.
enum AuthoredFileKind: Equatable, Sendable {
  /// A use case file, or use case input: unquoted text followed by a comment is refused.
  case useCase

  /// A settings file: end-of-line comments are kept.
  case settings
}
