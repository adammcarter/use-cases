extension UseCaseDefinition {
  /// The same use case with this sign-off, or none.
  func approved(_ approval: Approval?) -> UseCaseDefinition {
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
}
