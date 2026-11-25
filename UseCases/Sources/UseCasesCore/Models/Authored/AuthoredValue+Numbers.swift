extension AuthoredValue {
  /// The value as a number when it is one, whether written as an integer or not.
  var numericValue: Double? {
    switch self {
    case let .integer(integer): Double(integer)
    case let .number(number): number
    default: nil
    }
  }
}

extension Double {
  /// The number as a failure message shows it: a whole number without its `.0`.
  var schemaNumberText: String {
    if let integer = Int(exactly: self) {
      return String(integer)
    }

    return String(self)
  }
}
