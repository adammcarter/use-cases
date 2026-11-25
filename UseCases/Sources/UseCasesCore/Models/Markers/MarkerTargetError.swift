/// Why the id after a sentinel is not a marker id (chapter 05 "Derived marker identities").
enum MarkerTargetError: Error, Equatable, Sendable {
  /// Nothing follows the sentinel.
  case empty

  /// No id follows the sentinel, but this text, which is not one, does.
  case emptyBeforeWord(String)

  /// The id run is directly followed by an ASCII letter, digit or underscore, so reading the id
  /// as the run would cut a word short.
  case runsIntoWord(String)

  /// There is no `#` between the use case and the binding.
  case missingSeparator

  /// There is more than one `#`.
  case severalSeparators

  /// After the `#` there are more than a route and a binding.
  case tooManyPiecesAfterSeparator

  /// What comes before the `#` is not a use-case id.
  case invalidUseCase(IdentityError)

  /// The route written before the last `.` after the `#` is not a route id.
  case invalidRoute(IdentityError)

  /// What comes last after the `#` is not a binding id.
  case invalidBinding(IdentityError)
}

extension MarkerTargetError: CustomStringConvertible {
  var description: String {
    switch self {
    case .empty:
      "no marker id follows the sentinel"
    case let .emptyBeforeWord(word):
      "no marker id follows the sentinel; '\(word)' follows it, and an id is lowercase a-z, "
        + "0-9, '.', '#' and '-'"
    case let .runsIntoWord(word):
      "'\(word)' follows the id directly; an id ends at a character that is not a letter, "
        + "a digit or an underscore"
    case .missingSeparator:
      "a marker id has a '#' between the use case and the binding"
    case .severalSeparators:
      "a marker id has only one '#'"
    case .tooManyPiecesAfterSeparator:
      "after the '#' a marker id has a binding, or a route and a binding joined with '.'"
    case let .invalidUseCase(error):
      "the use case id is not valid: \(error.reason)"
    case let .invalidRoute(error):
      "the route id is not valid: \(error.reason)"
    case let .invalidBinding(error):
      "the binding id is not valid: \(error.reason)"
    }
  }
}
