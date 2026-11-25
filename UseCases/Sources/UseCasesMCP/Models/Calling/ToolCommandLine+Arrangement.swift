import MCP

extension ToolCommandLine {
  /// The parts of a command line as the arguments of a call are placed one by one.
  struct Arrangement {
    /// The options, each with its value.
    private(set) var options: [String] = []

    /// The values that go after `--`.
    private(set) var positionals: [String] = []

    /// The values that go on standard input, by argument name.
    private(set) var inputMembers: [String: Value] = [:]

    /// Places the value of `argument` where its placement says.
    mutating func place(
      _ value: Value,
      for argument: ToolArgument,
    ) throws(ToolCommandLineError) {
      switch argument.placement {
      case .workspace, .option, .commaSeparated, .repeated, .flag:
        try placeOption(
          value,
          for: argument,
        )
      case .positional, .positionalList, .flagOrPositional:
        try placePositional(
          value,
          for: argument,
        )
      case .standardInput:
        inputMembers[argument.name] = value
      }
    }

    private mutating func placeOption(
      _ value: Value,
      for argument: ToolArgument,
    ) throws(ToolCommandLineError) {
      switch argument.placement {
      case .workspace:
        try options += Self.option("--workspace", Self.text(of: value, for: argument))
      case let .option(flag):
        try options += Self.option(flag, Self.text(of: value, for: argument))
      case let .commaSeparated(flag):
        let texts = try Self.texts(of: value, for: argument)

        guard !texts.contains(where: Self.holdsComma) else {
          throw .holdsComma(argument: argument.name)
        }

        options += Self.option(flag, texts.joined(separator: ","))
      case let .repeated(flag):
        for text in try Self.texts(of: value, for: argument) {
          options += Self.option(flag, text)
        }
      case let .flag(flag):
        if value.boolValue == true {
          options.append(flag)
        }
      case .positional, .positionalList, .flagOrPositional, .standardInput:
        break
      }
    }

    private mutating func placePositional(
      _ value: Value,
      for argument: ToolArgument,
    ) throws(ToolCommandLineError) {
      switch argument.placement {
      case .positional:
        try positionals.append(Self.text(of: value, for: argument))
      case .positionalList:
        try positionals += Self.texts(of: value, for: argument)
      case let .flagOrPositional(known):
        try place(
          Self.text(of: value, for: argument),
          knownAs: known,
        )
      case .workspace, .option, .commaSeparated, .repeated, .flag, .standardInput:
        break
      }
    }

    /// A value the tool names as a step is its flag; any other goes after `--` as it is.
    private mutating func place(
      _ text: String,
      knownAs known: [String],
    ) {
      if known.contains(text) {
        options.append("--\(text)")
      } else {
        positionals.append(text)
      }
    }

    private static func holdsComma(_ text: String) -> Bool {
      text.contains(",")
    }

    /// An option and its value. A value that starts with `-` is joined to its option with `=`,
    /// or the command would read it as another option.
    private static func option(
      _ flag: String,
      _ text: String,
    ) -> [String] {
      text.hasPrefix("-") ? ["\(flag)=\(text)"] : [flag, text]
    }

    private static func text(
      of value: Value,
      for argument: ToolArgument,
    ) throws(ToolCommandLineError) -> String {
      guard let text = value.argumentText else {
        throw .unusable(argument: argument.name)
      }

      guard !text.unicodeScalars.contains("\0") else {
        throw .holdsNull(argument: argument.name)
      }

      return text
    }

    private static func texts(
      of value: Value,
      for argument: ToolArgument,
    ) throws(ToolCommandLineError) -> [String] {
      guard case let .array(items) = value else {
        throw .unusable(argument: argument.name)
      }

      var texts: [String] = []
      for item in items {
        try texts.append(text(of: item, for: argument))
      }

      return texts
    }
  }
}
