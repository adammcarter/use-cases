/// What a call becomes when it is run: the arguments after the program, and the text the command
/// reads on its standard input.
struct ToolCommandLine: Equatable, Sendable {
  /// The command's name first, then `--json`, the options, and the values after `--`.
  let arguments: [String]

  /// `nil` when the command reads none.
  let standardInput: String?
}
