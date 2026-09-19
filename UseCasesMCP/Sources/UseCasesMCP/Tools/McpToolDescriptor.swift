import UseCasesCore

/// One tool as `tools/list` advertises it (packages/mcp/src/tools.ts
/// `McpToolDescriptor`).
///
/// `command` and `mutability` are not MCP's own fields: they say which CLI
/// command answers the call and whether it writes, which is what lets a host
/// decide before calling. Their position in the object — second and last — is
/// part of the recorded wire form.
public struct McpToolDescriptor: Sendable, Equatable {
  /// What a call is allowed to do. `write` demands both locks; an
  /// `approval_request` may ask for a human decision but never record one.
  public enum Mutability: String, Sendable, Equatable {
    case read
    case write
    case approvalRequest = "approval_request"
  }

  public let name: String
  public let command: String
  public let description: String
  public let inputSchema: JSONValue
  public let outputSchema: JSONValue
  public let mutability: Mutability

  public init(
    name: String,
    command: String,
    description: String,
    inputSchema: JSONValue,
    outputSchema: JSONValue,
    mutability: Mutability,
  ) {
    self.name = name
    self.command = command
    self.description = description
    self.inputSchema = inputSchema
    self.outputSchema = outputSchema
    self.mutability = mutability
  }

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("name", .string(name)),
      ("command", .string(command)),
      ("description", .string(description)),
      ("inputSchema", inputSchema),
      ("outputSchema", outputSchema),
      ("mutability", .string(mutability.rawValue)),
    ]))
  }
}
