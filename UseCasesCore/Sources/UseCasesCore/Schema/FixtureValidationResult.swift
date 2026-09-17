/// The outcome of validating a whole workspace of fixture files.
public struct FixtureValidationResult: Sendable, Equatable {
  public let isValid: Bool
  public let isComplete: Bool
  public let diagnostics: [Diagnostic]
  public let validatedSchemaIdentifiers: [String]
  public let expectedState: JSONValue?

  public init(
    isValid: Bool,
    isComplete: Bool,
    diagnostics: [Diagnostic],
    validatedSchemaIdentifiers: [String],
    expectedState: JSONValue?,
  ) {
    self.isValid = isValid
    self.isComplete = isComplete
    self.diagnostics = diagnostics
    self.validatedSchemaIdentifiers = validatedSchemaIdentifiers
    self.expectedState = expectedState
  }
}
