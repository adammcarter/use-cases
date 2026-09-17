/// What validating the shipped skill assets found
/// (`SkillAssetValidationResult`).
public struct SkillAssetValidationResult: Sendable, Equatable {
  /// No diagnostic is an error.
  public let isComplete: Bool
  public let skills: [SkillAssetSummary]
  public let hostRegistration: SkillHostRegistrationResult
  public let bootstrap: SkillBootstrapSummary
  public let commandReferences: [SkillCommandReference]
  public let diagnostics: [Diagnostic]

  public init(
    skills: [SkillAssetSummary],
    hostRegistration: SkillHostRegistrationResult,
    bootstrap: SkillBootstrapSummary,
    commandReferences: [SkillCommandReference],
    diagnostics: [Diagnostic],
  ) {
    isComplete = diagnostics.allSatisfy { diagnostic in
      diagnostic.severity != .error
    }
    self.skills = skills
    self.hostRegistration = hostRegistration
    self.bootstrap = bootstrap
    self.commandReferences = commandReferences
    self.diagnostics = diagnostics
  }

  /// The TypeScript's result object, members in its order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("skill_count", .number(Double(skills.count))),
      ("skills", .array(skills.map(\.jsonValue))),
      ("host_registration", hostRegistration.jsonValue),
      ("bootstrap", bootstrap.jsonValue),
      ("command_references", .array(commandReferences.map(\.jsonValue))),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
