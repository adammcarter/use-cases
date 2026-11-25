extension String {
  /// Whether both texts are the same Unicode scalars, in the same order.
  func hasSameScalars(as other: String) -> Bool {
    unicodeScalars.elementsEqual(other.unicodeScalars)
  }

  /// Whether this text comes before the other by comparing Unicode scalar values.
  func precedesByScalars(_ other: String) -> Bool {
    unicodeScalars.lexicographicallyPrecedes(other.unicodeScalars)
  }
}
