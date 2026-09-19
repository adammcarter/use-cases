/// The skills the plugin ships (`CANONICAL_SKILLS`), in the TypeScript's
/// order. The one list host projection, skill-asset validation and the
/// activation decision tree all read.
public enum CanonicalSkill: String, Sendable, Equatable, CaseIterable {
  case useCases = "use-cases"
  case showcase
  case walkthrough
  case initialize = "init"
  case useCaseDrivenDevelopment = "use-case-driven-development"
}
