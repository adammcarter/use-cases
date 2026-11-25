extension AuthoredObject {
  /// The list of lists of text under the key; an absent list is an empty one.
  func lists(_ key: String) throws(AuthoredShapeError) -> [[String]] {
    var lists: [[String]] = []

    for item in try items(key) {
      guard case let .array(texts) = item else {
        throw .wrongType(
          location: location(of: key),
          expected: "a list of lists",
        )
      }

      var words: [String] = []

      for text in texts {
        guard case let .string(word) = text else {
          throw .wrongType(
            location: location(of: key),
            expected: "text",
          )
        }

        words.append(word)
      }

      lists.append(words)
    }

    return lists
  }
}
