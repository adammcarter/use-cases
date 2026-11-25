/// What a use case promises (chapter 11 §89.9, chapter 02 `approved`): its words, never how they
/// are proven.
struct PromiseFingerprintInput: Sendable {
  /// The fully resolved id.
  let useCase: UseCaseIdentifier
  let title: String
  let description: String?
  let valueTier: ValueTier?
  let intent: String?

  /// In the order written.
  let scenarios: [Scenario]

  /// In the order written.
  let outOfScope: [String]

  /// The promise of a definition, once its id has been composed.
  init(
    definition: UseCaseDefinition,
    identifier: UseCaseIdentifier,
  ) {
    self.init(
      useCase: identifier,
      title: definition.title,
      description: definition.description,
      valueTier: definition.valueTier,
      intent: definition.intent,
      scenarios: definition.scenarios,
      outOfScope: definition.outOfScope,
    )
  }

  init(
    useCase: UseCaseIdentifier,
    title: String,
    description: String?,
    valueTier: ValueTier?,
    intent: String?,
    scenarios: [Scenario],
    outOfScope: [String],
  ) {
    self.useCase = useCase
    self.title = title
    self.description = description
    self.valueTier = valueTier
    self.intent = intent
    self.scenarios = scenarios
    self.outOfScope = outOfScope
  }
}
