import MCP

/// Checks the arguments of a call against the tool's own input schema.
protocol ToolArgumentChecking: Sendable {
  /// What is wrong with the arguments, as one sentence per problem joined by `; `; `nil` when
  /// they are right. A value the command line would refuse, such as a word that is no step, is
  /// not a problem here: the command line refuses it in its own words.
  func refusal(of arguments: [String: Value]) -> String?
}
