/// Why `--hooks` could not be read.
enum InitHooksFlagError: Error, Equatable {
  /// The value is not `commit`, `push` or `commit,push`.
  case notHooks(String)

  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case let .notHooks(value):
      "--hooks takes commit, push or commit,push; not '\(value)'"
    }
  }
}
