extension [String] {
  /// Whether any line contains the text.
  func mentions(_ text: String) -> Bool {
    contains { line in
      line.contains(text)
    }
  }
}

extension [String] {
  /// The place of the first line that contains the text.
  func firstIndexMentioning(_ text: String) -> Int? {
    firstIndex { line in
      line.contains(text)
    }
  }
}
