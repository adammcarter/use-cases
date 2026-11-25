/// Reads the text of a JSON document into the value an authored file reads as.
protocol JSONReading: Sendable {
  /// Reads one JSON document. An integer stays an integer, any other number stays a number,
  /// and an object keeps its members in the order they were written.
  func read(_ text: String) throws(JSONReadingError) -> AuthoredValue
}
