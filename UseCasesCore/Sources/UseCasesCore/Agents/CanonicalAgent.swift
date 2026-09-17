/// The agents the plugin ships (`CANONICAL_AGENTS`), in the TypeScript's
/// order: the agents directory listing, the Claude plugin manifest and the
/// published package files are all validated against this one list.
///
/// The three form one loop: `use-cases-updater` keeps the matrix honest against
/// the code, `use-cases-demo-prep` stages a demo from it, `use-cases-demo`
/// performs that demo and records the evidence.
public enum CanonicalAgent: String, Sendable, Equatable, CaseIterable {
  case useCasesUpdater = "use-cases-updater"
  case useCasesDemoPreparation = "use-cases-demo-prep"
  case useCasesDemo = "use-cases-demo"
}
