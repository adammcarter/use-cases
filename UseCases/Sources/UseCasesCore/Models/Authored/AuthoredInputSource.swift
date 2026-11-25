/// Where authored input comes from: a file, or the standard input (`-`).
enum AuthoredInputSource: Equatable, Sendable {
  case standardInput

  /// A file, by the path as it was typed.
  case file(String)

  /// What a command line names: `-` is the standard input, anything else a file.
  init(argument: String) {
    self = argument == "-" ? .standardInput : .file(argument)
  }

  /// What every refusal about the input calls it: `stdin`, or the path as typed.
  var name: String {
    switch self {
    case .standardInput:
      "stdin"
    case let .file(path):
      path
    }
  }
}
