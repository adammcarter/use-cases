/// Reading the texts out of a document.
extension JSONValue {
  /// The strings of an array, in order; empty for anything else.
  var strings: [String] {
    guard case let .array(items) = self else {
      return []
    }

    return items.compactMap { item in
      guard case let .string(text) = item else {
        return nil
      }

      return text
    }
  }
}
