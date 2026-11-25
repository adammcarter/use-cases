/// Reads what is piped to the command.
protocol StandardInputReading: Sendable {
  /// Everything on the standard input, up to its end.
  func readText() throws(AuthoredInputError) -> String
}
