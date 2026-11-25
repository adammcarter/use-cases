/// What a schema says of the members it does not list under `properties`.
enum AdditionalProperties: Equatable, Sendable {
  /// `additionalProperties: false`
  case forbidden

  /// A schema every unlisted member must satisfy, by the index of its node.
  case schema(Int)
}
