/// Whether every host can load the skills (`SkillHostRegistrationResult`).
public struct SkillHostRegistrationResult: Sendable, Equatable {
  public let isComplete: Bool
  public let hosts: [SkillHostRegistrationSummary]

  public init(
    isComplete: Bool,
    hosts: [SkillHostRegistrationSummary],
  ) {
    self.isComplete = isComplete
    self.hosts = hosts
  }

  /// `{ complete, hosts }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("complete", .bool(isComplete)),
      ("hosts", .array(hosts.map(\.jsonValue))),
    ]))
  }
}
