/// One argument of a tool: what the agent may send, and where it goes on the command line.
struct ToolArgument: Equatable, Sendable {
  let name: String
  let type: ToolArgumentType
  let placement: ToolArgumentPlacement
  let description: String
  var isRequired = false

  /// The values the description names, which the input schema lists too: for a list, the values
  /// of its items. The server does not enforce them: the command line refuses a value it does
  /// not take, in its own words.
  var allowedValues: [String] = []

  /// The whole numbers the description names, which the input schema gives as its minimum and
  /// maximum. Not enforced by the server either.
  var range: ClosedRange<Int>?
}
