/// A comment found in a definition file, with where it is.
struct FileComment: Equatable, Sendable {
  /// The line, counted from 1.
  let line: Int

  /// The comment as written, from its `#`.
  let text: String
}
