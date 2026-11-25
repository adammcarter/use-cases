extension String {
  /// Splits on one Unicode scalar and keeps every empty piece, so `a..b` gives three pieces.
  /// Splitting scalar by scalar matters: a separator followed by a combining mark is one
  /// `Character`, and a split by `Character` would not see the separator.
  func splitOnScalar(_ separator: Unicode.Scalar) -> [String] {
    unicodeScalars
      .split(
        separator: separator,
        omittingEmptySubsequences: false,
      )
      .map { piece in
        String(piece)
      }
  }
}
