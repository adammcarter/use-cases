/// Why a call's arguments cannot be made into a command line.
enum ToolCommandLineError: Error, Equatable {
  /// A value is not one the argument's type can be written as, or cannot be written as JSON.
  case unusable(argument: String)

  /// A text holds U+0000, which ends a word of a command line: the command would read less than
  /// was sent.
  case holdsNull(argument: String)

  /// An item of a list the command reads as one comma-joined value holds a comma: the command
  /// would read two values where one was sent.
  case holdsComma(argument: String)

  /// The argument whose value could not be passed.
  var argument: String {
    switch self {
    case let .unusable(argument), let .holdsNull(argument), let .holdsComma(argument):
      argument
    }
  }

  /// What is wrong, as the refusal says it.
  var message: String {
    switch self {
    case let .unusable(argument):
      "the value of \(argument) cannot be passed to the command"
    case let .holdsNull(argument):
      "\(argument) holds a NUL character (U+0000), which a command line cannot carry"
    case let .holdsComma(argument):
      "an item of \(argument) holds a comma, which the command would read as two values"
    }
  }
}
