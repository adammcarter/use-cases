import UseCasesCore

/// One outbound JSON-RPC message. Its three keys and their order are wire
/// contract, so the bytes come from ``JSONWriter`` rather than an encoder
/// (ADR 0007 decision 8).
public struct JsonRpcResponse: Sendable, Equatable {
  /// A response carries a result or an error, never both.
  public enum Payload: Sendable, Equatable {
    case result(JSONValue)
    case failure(code: Int, message: String)
  }

  public let identifier: JSONValue
  public let payload: Payload

  public init(
    identifier: JSONValue,
    payload: Payload,
  ) {
    self.identifier = identifier
    self.payload = payload
  }

  public static func result(
    _ value: JSONValue,
    identifier: JSONValue,
  ) -> JsonRpcResponse {
    JsonRpcResponse(identifier: identifier, payload: .result(value))
  }

  public static func failure(
    code: Int,
    message: String,
    identifier: JSONValue,
  ) -> JsonRpcResponse {
    JsonRpcResponse(identifier: identifier, payload: .failure(code: code, message: message))
  }

  /// `{"jsonrpc":"2.0","id":…,"error":{"code":-32700,"message":"Parse error"}}`
  /// — the answer to a line `JSON.parse` refused.
  public static let parseError = JsonRpcResponse(
    identifier: .null,
    payload: .failure(code: -32700, message: "Parse error"),
  )

  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("jsonrpc", .string("2.0")),
      ("id", identifier),
    ])
    switch payload {
    case let .result(value):
      object["result"] = value
    case let .failure(code, message):
      object["error"] = .object(JSONObject([
        ("code", .number(Double(code))),
        ("message", .string(message)),
      ]))
    }
    return .object(object)
  }

  public var jsonText: String {
    JSONWriter.encode(jsonValue)
  }
}
