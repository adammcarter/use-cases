/// The bootstrap document, as read (`SkillBootstrapSummary`).
public struct SkillBootstrapSummary: Sendable, Equatable {
  public let path: String
  /// Every required section is present.
  public let isComplete: Bool
  /// The required sections found, in the required order.
  public let sections: [String]

  public init(
    path: String,
    isComplete: Bool,
    sections: [String],
  ) {
    self.path = path
    self.isComplete = isComplete
    self.sections = sections
  }

  /// `{ path, complete, sections }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("path", .string(path)),
      ("complete", .bool(isComplete)),
      ("sections", .array(sections.map(JSONValue.string))),
    ]))
  }
}
