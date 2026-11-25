extension String {
  /// The text followed by spaces, to at least `width` characters.
  func padded(toWidth width: Int) -> String {
    self + String(
      repeating: " ",
      count: max(0, width - count),
    )
  }
}
