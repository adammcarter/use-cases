/// The outcome of looking for a test's declaration in the source.
enum DeclarationSearch: Equatable, Sendable {
  case missing
  /// Found `count` times: never guessed between.
  case ambiguous(count: Int)
  case found(file: String, line: Int)
}
