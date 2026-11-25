extension Optional where Wrapped: Comparable {
  /// Orders a missing value before any value, and values among themselves.
  func precedesNilFirst(_ other: Wrapped?) -> Bool {
    switch (self, other) {
    case (.none, .some):
      true
    case let (.some(lhs), .some(rhs)):
      lhs < rhs
    default:
      false
    }
  }
}
