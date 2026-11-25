/// Answers the command list, a command that does not exist, and one designed but not built yet.
/// `help` is not a command of chapter 16 §2, so it is no command here; `--help` is the way to ask.
struct CommandSurface: CommandSurfacing {
  func answer(to arguments: [String]) -> CommandResult? {
    let words = CommandWords(arguments)

    guard let word = words.command else {
      return words.asksForHelp || arguments.isEmpty ? .done(CommandList.text) : nil
    }

    guard let command = DesignedCommand(rawValue: word) else {
      return .refusal(
        .usage,
        message: "invalid choice: '\(word)' (choose from \(Self.choices))",
        command: nil,
        json: words.asksForJSON,
      )
    }

    return command.isBuilt ? nil : .notBuiltYet(command: command.rawValue)
  }

  private static let choices = DesignedCommand.allCases.map(\.rawValue).joined(separator: ", ")
}
