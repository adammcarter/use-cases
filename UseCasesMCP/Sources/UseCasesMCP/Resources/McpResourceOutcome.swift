import UseCasesCore

/// What a `resources/read` produced: the contents, or the JSON-RPC error the
/// read is reported as.
///
/// The two codes are MCP 2025-11-25's: -32602 invalid params for a repo the
/// caller cannot use, -32002 resource not found for a URI that names nothing.
public enum McpResourceOutcome: Sendable, Equatable {
  case contents(uri: String, payload: JSONValue)
  case failure(code: Int, message: String)

  public static let invalidParameters = -32602
  public static let resourceNotFound = -32002

  /// `contents: [{ uri, mimeType, text }]` — the payload as a JSON string,
  /// which is what an MCP resource carries.
  public var jsonValue: JSONValue? {
    guard case let .contents(uri, payload) = self else {
      return nil
    }
    return .object(JSONObject([
      ("contents", .array([
        .object(JSONObject([
          ("uri", .string(uri)),
          ("mimeType", .string(McpResourceCatalog.jsonMimeType)),
          ("text", .string(JSONWriter.encode(payload))),
        ])),
      ])),
    ]))
  }
}
