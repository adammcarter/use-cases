import UseCasesCore

/// The whole protocol surface, one message at a time
/// (packages/mcp/src/index.ts `handleMcpMessage`).
///
/// It is deliberately stateless: `initialize` is answered every time it is
/// asked, and nothing is refused for arriving "too early". A host that
/// re-handshakes, or that never sends `notifications/initialized`, is answered
/// the same as one that follows the lifecycle exactly.
public enum McpMessageRouter {
  /// The negotiated protocol version. It is stated, not negotiated: the server
  /// answers this version whatever the client asked for.
  public static let protocolVersion = "2025-11-25"

  /// The response to send, or nil for a notification, which is answered with
  /// silence.
  public static func respond(
    to request: JsonRpcRequest,
    environment: McpEnvironment,
  ) async -> JsonRpcResponse? {
    if request.method == "notifications/initialized" {
      return nil
    }
    let identifier = request.identifier

    switch request.method {
    case "initialize":
      return .result(initializeResult, identifier: identifier)
    case "tools/list":
      return .result(
        listing("tools", McpToolCatalog.descriptors.map(\.jsonValue)),
        identifier: identifier,
      )
    case "tools/call":
      return await called(request, environment, identifier)
    case "resources/list":
      return .result(
        listing("resources", McpResourceCatalog.descriptors.map(\.jsonValue)),
        identifier: identifier,
      )
    case "resources/read":
      return read(request, environment, identifier)
    case "prompts/list":
      return .result(
        listing("prompts", McpPromptCatalog.descriptors.map(\.jsonValue)),
        identifier: identifier,
      )
    case "prompts/get":
      return prompt(request, identifier)
    default:
      return .failure(
        code: -32601,
        message: "Method not found: \(request.methodText)",
        identifier: identifier,
      )
    }
  }

  /// The three list methods answer the same shape: one key naming the array.
  private static func listing(
    _ key: String,
    _ entries: [JSONValue],
  ) -> JSONValue {
    .object(JSONObject([(key, .array(entries))]))
  }

  private static func called(
    _ request: JsonRpcRequest,
    _ environment: McpEnvironment,
    _ identifier: JSONValue,
  ) async -> JsonRpcResponse {
    let envelope = await McpToolCatalog.call(
      name: request.parameters["name"]?.stringValue ?? "",
      arguments: request.parameters["arguments"]?.objectValue ?? JSONObject(),
      environment: environment,
    )
    return .result(callResult(envelope), identifier: identifier)
  }

  private static func read(
    _ request: JsonRpcRequest,
    _ environment: McpEnvironment,
    _ identifier: JSONValue,
  ) -> JsonRpcResponse {
    let outcome = McpResourceReader.read(
      uri: request.parameters["uri"]?.stringValue ?? "",
      environment: environment,
    )
    switch outcome {
    case .contents:
      return .result(outcome.jsonValue ?? .null, identifier: identifier)
    case let .failure(code, message):
      return .failure(code: code, message: message, identifier: identifier)
    }
  }

  private static func prompt(
    _ request: JsonRpcRequest,
    _ identifier: JSONValue,
  ) -> JsonRpcResponse {
    let outcome = McpPromptCatalog.prompt(
      named: request.parameters["name"]?.stringValue ?? "",
      arguments: request.parameters["arguments"]?.objectValue ?? JSONObject(),
    )
    switch outcome {
    case let .result(built):
      return .result(built.jsonValue, identifier: identifier)
    case let .failure(code, message):
      return .failure(code: code, message: message, identifier: identifier)
    }
  }

  /// Tools, resources and prompts are all advertised; nothing else is.
  static let initializeResult = JSONValue.object(JSONObject([
    ("protocolVersion", .string(protocolVersion)),
    ("capabilities", .object(JSONObject([
      ("tools", .object(JSONObject())),
      ("resources", .object(JSONObject())),
      ("prompts", .object(JSONObject())),
    ]))),
    ("serverInfo", .object(JSONObject([
      ("name", .string(ProductVersion.productName)),
      ("version", .string(ProductVersion.version)),
    ]))),
  ]))

  /// A tool result carries the envelope twice: as text, for a host that only
  /// reads content, and as `structuredContent` for one that reads JSON.
  ///
  /// `isError` is always false — a domain refusal is a RESULT, not a broken
  /// call, and the envelope's own `ok` carries it.
  static func callResult(_ envelope: CliResult) -> JSONValue {
    .object(JSONObject([
      ("content", .array([
        .object(JSONObject([
          ("type", .string("text")),
          ("text", .string(envelope.jsonText())),
        ])),
      ])),
      ("structuredContent", envelope.jsonValue()),
      ("isError", .bool(false)),
    ]))
  }
}
