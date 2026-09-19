import UseCasesCore

/// What `prompts/get` answers: a description and the messages that carry the
/// guidance. Prompts are PURE TEXT — they never execute a command, run a
/// verifier or mint a proof.
public struct McpPromptResult: Sendable, Equatable {
  public let description: String
  public let text: String

  public init(
    description: String,
    text: String,
  ) {
    self.description = description
    self.text = text
  }

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("description", .string(description)),
      ("messages", .array([
        .object(JSONObject([
          ("role", .string("user")),
          ("content", .object(JSONObject([
            ("type", .string("text")),
            ("text", .string(text)),
          ]))),
        ])),
      ])),
    ]))
  }
}
