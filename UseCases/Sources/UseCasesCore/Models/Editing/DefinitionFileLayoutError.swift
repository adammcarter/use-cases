/// Why the use cases of a definition file cannot be found by their lines.
enum DefinitionFileLayoutError: Error, Equatable, Sendable {
  /// There is no plain `use_cases:` key at the start of a line.
  case notFound

  /// The key does not hold a list written one use case to a `- `.
  case notAList

  /// The reason in words.
  var message: String {
    switch self {
    case .notFound:
      "it has no `use_cases:` key at the start of a line"
    case .notAList:
      "its use cases are not written as a list with a `- ` for each"
    }
  }
}
