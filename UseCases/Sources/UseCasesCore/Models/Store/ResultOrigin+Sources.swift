extension ResultOrigin {
  /// Where the verdict came from, as a person is told it: the validations whose reports gave it,
  /// or `record`.
  var sources: [String] {
    switch self {
    case .recorded:
      ["record"]
    case let .validations(identifiers, _):
      identifiers.map(\.text)
    }
  }
}
