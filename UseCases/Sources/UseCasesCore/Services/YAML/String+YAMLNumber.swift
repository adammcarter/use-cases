extension String {
  /// Whether a plain scalar could be read as a number or a date: only text that starts with a
  /// digit, a sign or a point can be, so everything else skips the slow pattern matching.
  var startsLikeANumber: Bool {
    guard let first = unicodeScalars.first else {
      return false
    }

    return ("0" ... "9").contains(first) || first == "+" || first == "-" || first == "."
  }

  /// Whether the text is one or more ASCII digits and nothing else.
  var isDecimalDigits: Bool {
    guard !isEmpty else {
      return false
    }

    for scalar in unicodeScalars where !("0" ... "9").contains(scalar) {
      return false
    }

    return true
  }
}
