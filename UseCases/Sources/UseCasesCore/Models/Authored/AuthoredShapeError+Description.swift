extension AuthoredShapeError: CustomStringConvertible {
  /// Where in the value the problem is, empty for the value itself.
  var location: String {
    switch self {
    case let .notAnObject(location),
         let .missing(location),
         let .wrongType(location, _),
         let .unknownChoice(location, _),
         let .invalidIdentifier(location, _),
         let .invalidPath(location, _),
         let .invalidPattern(location, _),
         let .invalidPosition(location, _),
         let .invalidDate(location, _),
         let .invalidValue(location, _):
      location
    }
  }

  /// What is wrong, without where.
  var reason: String {
    switch self {
    case .notAnObject:
      "this must be a mapping"
    case .missing:
      "this is required"
    case let .wrongType(_, expected):
      "this must be \(expected)"
    case let .unknownChoice(_, text):
      "\(AuthoredValue.quote(text)) is not one of the values this field allows"
    case let .invalidIdentifier(_, error):
      error.description
    case let .invalidPath(_, error):
      error.description
    case let .invalidPattern(_, error):
      error.description
    case let .invalidPosition(_, error):
      switch error {
      case let .lineBelowOne(line):
        "line \(line) is below 1; lines count from 1"
      case let .columnBelowOne(column):
        "column \(column) is below 1; columns count from 1"
      }
    case let .invalidDate(_, text):
      "\(AuthoredValue.quote(text)) is not a day written YYYY-MM-DD"
    case let .invalidValue(_, reason):
      reason
    }
  }

  /// The location, then the reason: `scenarios[1].id: '...' is not a valid id: ...`.
  var description: String {
    location.isEmpty ? reason : "\(location): \(reason)"
  }
}
