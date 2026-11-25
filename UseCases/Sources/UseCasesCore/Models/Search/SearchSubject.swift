/// What a search looks for.
public enum SearchSubject: Equatable, Sendable {
  /// Words as typed, with `"phrases"` and `-words` to leave out.
  case words(String)

  /// A whole use case: a file or `-` for the standard input, as `save` takes one.
  case like(String)
}
