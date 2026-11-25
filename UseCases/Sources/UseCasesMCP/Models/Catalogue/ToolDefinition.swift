import MCP

/// One tool of chapter 20 §3, as data: what it is called, what it runs, what it takes and what
/// it promises the host.
struct ToolDefinition: Equatable, Sendable {
  /// The tool's name, which says what it acts on; the commands keep their short names.
  let name: String

  /// The name for people.
  let title: String

  /// What the tool does, and what its answer is not.
  let description: String

  /// The command it runs, as the command line spells it, and as the `command` of its documents.
  let command: String

  /// What it takes, in the order positional values go on the command line.
  let arguments: [ToolArgument]

  let input: ToolInput

  /// What the host may assume about the tool; hints, never guarantees.
  let annotations: Tool.Annotations

  /// The published schema of the command's document (`docs/schemas/output`).
  let outputSchemaFile: String

  init(
    name: String,
    title: String,
    description: String,
    command: String,
    arguments: [ToolArgument],
    input: ToolInput = .none,
    annotations: Tool.Annotations,
    outputSchemaFile: String,
  ) {
    self.name = name
    self.title = title
    self.description = description
    self.command = command
    self.arguments = arguments
    self.input = input
    self.annotations = annotations
    self.outputSchemaFile = outputSchemaFile
  }

  /// The tool's input schema: an object that takes exactly these arguments, and no others.
  var inputSchema: Value {
    .object([
      "type": .string("object"),
      "properties": .object(
        Dictionary(
          uniqueKeysWithValues: arguments.map { argument in
            (argument.name, argument.schema)
          },
        ),
      ),
      "required": .array(
        arguments.filter(\.isRequired).map { argument in
          .string(argument.name)
        },
      ),
      "additionalProperties": .bool(false),
    ])
  }
}
