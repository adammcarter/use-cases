import UseCasesCore

/// A tool and the handler behind it. Only the descriptor half reaches the wire.
public struct McpToolDefinition: Sendable {
  public typealias Handler = @Sendable (JSONObject, McpEnvironment) async throws(McpToolFailure)
    -> CliResult

  public let descriptor: McpToolDescriptor
  public let handler: Handler

  public init(
    name: String,
    command: String,
    description: String,
    mutability: McpToolDescriptor.Mutability,
    inputSchema: JSONValue,
    handler: @escaping Handler,
  ) {
    descriptor = McpToolDescriptor(
      name: name,
      command: command,
      description: description,
      inputSchema: inputSchema,
      outputSchema: McpToolSchemas.cliEnvelope,
      mutability: mutability,
    )
    self.handler = handler
  }

  public var name: String {
    descriptor.name
  }

  public var command: String {
    descriptor.command
  }

  public var mutability: McpToolDescriptor.Mutability {
    descriptor.mutability
  }
}
