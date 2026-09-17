/// Validates the shipped skills, bootstrap, activation docs and host
/// registration (packages/core/src/skills/validateSkillAssets.ts).
///
/// A document that exists but cannot be read, or a skills path that is not a
/// directory, is not a diagnostic: node's error escapes, as it does in the
/// TypeScript.
public enum SkillAssetValidator {
  static let bootstrapPath = "bootstrap/use-cases.md"
  static let activationPath = "docs/activation.md"

  static let bootstrapSections = [
    "When to apply",
    "When not to apply",
    "Trusted boundaries",
    "Default lifecycle",
    "Core commands",
    "Never claim",
  ]

  static let bootstrapBoundaries = [
    "repo data",
    "MCP output",
    "generated runbooks",
    "secrets",
    "private data",
  ]

  static let activationMarkers = [
    "Decision Tree",
    "-> use-cases",
    "-> showcase",
    "-> walkthrough",
    "-> do not activate",
  ]

  /// `validateSkillAssets`.
  public static func validate(context: ResolvedWorkspaceContext) throws(SkillAssetValidationError)
    -> SkillAssetValidationResult
  {
    let root = context.workspaceRoot
    var validation = SkillAssetValidation(root: root)
    try validation.checkSkillDirectory()
    try validation.readSkills()
    let sections = try validation.readBootstrap()
    try validation.readActivation()
    validation.checkCommandReferences()
    let hostRegistration = SkillHostRegistration.validate(
      root: root,
      diagnostics: &validation.diagnostics,
    )
    return SkillAssetValidationResult(
      skills: validation.skills,
      hostRegistration: hostRegistration,
      bootstrap: SkillBootstrapSummary(
        path: bootstrapPath,
        isComplete: bootstrapSections.allSatisfy(sections.contains),
        sections: sections,
      ),
      commandReferences: validation.commandReferences,
      diagnostics: validation.diagnostics,
    )
  }
}
