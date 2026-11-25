/// How a tool gives its command text on standard input (`--file -`, `--like -`).
enum ToolInput: Equatable, Sendable {
  /// The command reads no standard input.
  case none

  /// The argument's own JSON is the whole input, and `flag -` is passed with it, when the
  /// argument is given.
  case value(argument: String, flag: String)

  /// The arguments given are the members of one JSON object, which is the whole input, and
  /// `flag -` is always passed.
  case document(flag: String)
}
