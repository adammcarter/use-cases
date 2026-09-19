import UseCasesCore

/// One inbound JSON-RPC message, read exactly as the TypeScript server reads it
/// (packages/mcp/src/index.ts `JsonRpcRequest`): every member optional, and a
/// missing or `undefined` id answered as `null`.
public struct JsonRpcRequest: Sendable, Equatable {
  /// The id to answer with: the value as received, `null` when absent.
  public let identifier: JSONValue
  /// The method as received. Kept as JSON, not a string, because the
  /// unknown-method message interpolates whatever was sent.
  public let methodValue: JSONValue
  /// `isRecord(message.params) ? message.params : {}`.
  public let parameters: JSONObject

  /// The method when it is a string, which is the only way it matches a
  /// handler: `message.method === "initialize"` is false for anything else.
  public var method: String? {
    methodValue.stringValue
  }

  /// `${message.method ?? "<missing>"}`: absent and `null` both read as the
  /// placeholder, anything else as `String(value)`.
  public var methodText: String {
    methodValue == .null ? "<missing>" : Self.javaScriptText(methodValue)
  }

  /// `String(value)`, which is how a non-string method reaches the
  /// method-not-found message.
  private static func javaScriptText(_ value: JSONValue) -> String {
    switch value {
    case .null: "null"
    case let .bool(flag): flag ? "true" : "false"
    case let .number(number): JavaScriptNumber.text(number)
    case let .string(text): text
    case let .array(values): values.map(javaScriptText).joined(separator: ",")
    case .object: "[object Object]"
    }
  }

  public init(
    identifier: JSONValue,
    methodValue: JSONValue,
    parameters: JSONObject,
  ) {
    self.identifier = identifier
    self.methodValue = methodValue
    self.parameters = parameters
  }

  /// The message a parsed line describes. A line that is not an object still
  /// parses in JavaScript, and every member read off it is then `undefined`.
  public init(json: JSONValue) {
    let object = json.objectValue
    identifier = object?["id"] ?? .null
    methodValue = object?["method"] ?? .null
    parameters = object?["params"]?.objectValue ?? JSONObject()
  }
}
