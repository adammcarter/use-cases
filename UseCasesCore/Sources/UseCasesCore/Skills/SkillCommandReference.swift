/// A CLI command a skill body names (`SkillCommandReference`).
public struct SkillCommandReference: Sendable, Equatable {
  /// Its first two tokens, joined by one space.
  public let command: String
  public let sourcePath: String

  public init(
    command: String,
    sourcePath: String,
  ) {
    self.command = command
    self.sourcePath = sourcePath
  }

  /// `{ command, source_path }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("command", .string(command)),
      ("source_path", .string(sourcePath)),
    ]))
  }
}
