/// How a flag's value is read off the arguments.
enum FlagKind: Sendable, Equatable {
  /// Present or not.
  case boolean

  /// The token after the flag.
  case string

  /// The token after the flag, read as JavaScript's `Number` reads it.
  case integer
}
