import MCP

/// The error document of a call the server itself refuses: shaped as the command line's own
/// error document (`docs/schemas/output/cli-error.schema.json`, chapter 16 §5), so an agent
/// reads one shape for every refusal.
struct ToolErrorDocument: Equatable, Sendable {
  /// The shape version of every `--json` document (chapter 16 §5).
  static let outputVersion = 1

  /// The command the tool runs.
  let command: String

  /// The error kind: `usage`, because the call itself is wrong.
  let kind: String

  let message: String

  /// A call whose arguments are wrong: a missing, unknown or mistyped one.
  static func usage(
    command: String,
    message: String,
  ) -> ToolErrorDocument {
    ToolErrorDocument(
      command: command,
      kind: "usage",
      message: message,
    )
  }

  var value: Value {
    .object([
      "output_version": .int(Self.outputVersion),
      "command": .string(command),
      "error": .object([
        "kind": .string(kind),
        "message": .string(message),
      ]),
    ])
  }
}
