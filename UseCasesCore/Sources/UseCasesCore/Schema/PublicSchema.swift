/// One published schema: its id and, when it loaded, its body.
public struct PublicSchema: Sendable, Equatable {
  public let identifier: String
  public let schema: JSONValue?

  public init(
    identifier: String,
    schema: JSONValue?,
  ) {
    self.identifier = identifier
    self.schema = schema
  }
}
