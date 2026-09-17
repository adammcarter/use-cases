/// A capsule that loaded, where it came from, and its semantic hash
/// (`LoadedDemoCapsule`).
public struct LoadedDemoCapsule: Sendable, Equatable {
  /// The parsed document, members in the order JavaScript would enumerate
  /// them.
  public let capsule: JSONValue
  /// The typed reading of ``capsule``.
  public let definition: DemoCapsule
  /// Relative to the data root, with `/` separators.
  public let path: String
  public let semanticHash: String

  public init(
    capsule: JSONValue,
    definition: DemoCapsule,
    path: String,
    semanticHash: String,
  ) {
    self.capsule = capsule
    self.definition = definition
    self.path = path
    self.semanticHash = semanticHash
  }

  /// `{ capsule, path, semantic_hash }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("capsule", capsule),
      ("path", .string(path)),
      ("semantic_hash", .string(semanticHash)),
    ]))
  }
}
