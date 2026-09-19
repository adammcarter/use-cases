/// One canonical skill's `SKILL.md`, as read (`SkillAssetSummary`).
public struct SkillAssetSummary: Sendable, Equatable {
  /// The frontmatter name; empty when there is none.
  public let name: String
  public let path: String
  /// The frontmatter description; empty when there is none.
  public let description: String
  /// No diagnostic so far names this skill or its file.
  public let isComplete: Bool

  public init(
    name: String,
    path: String,
    description: String,
    isComplete: Bool,
  ) {
    self.name = name
    self.path = path
    self.description = description
    self.isComplete = isComplete
  }

  /// `{ name, path, description, complete }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("name", .string(name)),
      ("path", .string(path)),
      ("description", .string(description)),
      ("complete", .bool(isComplete)),
    ]))
  }
}
