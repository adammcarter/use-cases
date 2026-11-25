extension String {
  /// Whether nothing but white space is in it, a line break included.
  var isWhitespaceOnly: Bool {
    unicodeScalars.allSatisfy { scalar in
      scalar.properties.isWhitespace
    }
  }

  /// The text without the white space at either end.
  var withoutOuterWhitespace: String {
    let scalars = unicodeScalars
    let words = scalars.indices.filter { index in
      !scalars[index].properties.isWhitespace
    }

    guard let first = words.first, let last = words.last else {
      return ""
    }

    return String(scalars[first ... last])
  }
}
