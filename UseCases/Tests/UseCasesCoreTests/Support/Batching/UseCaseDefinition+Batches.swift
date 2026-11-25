@testable import UseCasesCore

extension UseCaseDefinition {
  /// The same use case under another title.
  func withTitle(_ title: String) -> UseCaseDefinition {
    UseCaseDefinition(
      localIdentifier: localIdentifier,
      title: title,
      description: description,
      valueTier: valueTier,
      intent: intent,
      outOfScope: outOfScope,
      scenarios: scenarios,
      routes: routes,
      bindings: bindings,
      approval: approval,
    )
  }

  /// The same use case under another id of its own.
  func withLocalIdentifier(_ local: String) throws -> UseCaseDefinition {
    try UseCaseDefinition(
      localIdentifier: IdentifierSegment(validating: local),
      title: title,
      description: description,
      valueTier: valueTier,
      intent: intent,
      outOfScope: outOfScope,
      scenarios: scenarios,
      routes: routes,
      bindings: bindings,
      approval: approval,
    )
  }
}
