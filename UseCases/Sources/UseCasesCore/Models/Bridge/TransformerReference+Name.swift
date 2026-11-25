extension TransformerReference {
  /// How a message names the transformer: the bundled name, or the program path as written.
  var name: String {
    switch self {
    case let .bundled(name):
      name
    case let .program(path):
      path.text
    }
  }
}
