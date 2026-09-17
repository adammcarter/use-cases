import UseCasesCore

/// One guided workflow as `prompts/list` advertises it.
public struct McpPromptDescriptor: Sendable, Equatable {
  /// One declared argument. `required` is always present, true or false.
  public struct Argument: Sendable, Equatable {
    public let name: String
    public let description: String
    public let isRequired: Bool

    public init(
      name: String,
      description: String,
      isRequired: Bool = false,
    ) {
      self.name = name
      self.description = description
      self.isRequired = isRequired
    }

    public var jsonValue: JSONValue {
      .object(JSONObject([
        ("name", .string(name)),
        ("description", .string(description)),
        ("required", .bool(isRequired)),
      ]))
    }
  }

  public let name: String
  public let description: String
  public let arguments: [Argument]

  public init(
    name: String,
    description: String,
    arguments: [Argument],
  ) {
    self.name = name
    self.description = description
    self.arguments = arguments
  }

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("name", .string(name)),
      ("description", .string(description)),
      ("arguments", .array(arguments.map(\.jsonValue))),
    ]))
  }
}
