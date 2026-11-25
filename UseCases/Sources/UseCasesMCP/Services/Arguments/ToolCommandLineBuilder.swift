import MCP

/// Builds the command line of a call. Every value an agent supplies is passed as it is, so the
/// command line's own words answer a value it refuses; the only value ever turned into a flag is
/// a step named in the tool's own table, and a positional value always follows `--`, so a value
/// that starts with `-` is never read as a flag.
struct ToolCommandLineBuilder: ToolCommandLineBuilding {
  private let writer: any JSONValueWriting

  init(writer: any JSONValueWriting = JSONValueWriter()) {
    self.writer = writer
  }

  func commandLine(
    for tool: ToolDefinition,
    arguments: [String: Value],
    workspace: String?,
  ) throws(ToolCommandLineError) -> ToolCommandLine {
    var arrangement = ToolCommandLine.Arrangement()

    for argument in tool.arguments {
      if let value = arguments[argument.name] {
        try arrangement.place(
          value,
          for: argument,
        )
      } else if argument.placement == .workspace, let workspace {
        try arrangement.place(
          .string(workspace),
          for: argument,
        )
      }
    }

    let input = try standardInput(
      of: tool,
      members: arrangement.inputMembers,
    )

    return ToolCommandLine(
      arguments: [tool.command, "--json"] + arrangement.options + input.options
        + (arrangement.positionals.isEmpty ? [] : ["--"] + arrangement.positionals),
      standardInput: input.text,
    )
  }

  /// The text on standard input, and the option that tells the command to read it.
  private func standardInput(
    of tool: ToolDefinition,
    members: [String: Value],
  ) throws(ToolCommandLineError) -> (options: [String], text: String?) {
    switch tool.input {
    case .none:
      return ([], nil)
    case let .value(argument, flag):
      guard let value = members[argument] else {
        return ([], nil)
      }

      return try ([flag, "-"], json(value, for: argument))
    case let .document(flag):
      return try ([flag, "-"], json(.object(members), for: tool.name))
    }
  }

  private func json(
    _ value: Value,
    for name: String,
  ) throws(ToolCommandLineError) -> String {
    guard let text = writer.text(of: value) else {
      throw .unusable(argument: name)
    }

    return text
  }
}
