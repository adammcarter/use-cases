import UseCasesCore

/// One resource as `resources/list` advertises it.
public struct McpResourceDescriptor: Sendable, Equatable {
  public let uri: String
  public let name: String
  public let description: String
  public let mimeType: String

  public init(
    uri: String,
    name: String,
    description: String,
    mimeType: String = McpResourceCatalog.jsonMimeType,
  ) {
    self.uri = uri
    self.name = name
    self.description = description
    self.mimeType = mimeType
  }

  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("uri", .string(uri)),
      ("name", .string(name)),
      ("description", .string(description)),
      ("mimeType", .string(mimeType)),
    ]))
  }
}
