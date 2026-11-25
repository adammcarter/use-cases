/// Checks the use case that `save` is sent, before anything is built from it (chapter 16 §14).
protocol UseCaseInputChecking: Sendable {
  /// The use case the input holds, held to the rules every definition file is held to: its
  /// fields, the technical ones that belong to the bridge settings, the schema, and the scenarios
  /// its routes cover.
  ///
  /// - Throws: ``UseCaseEditingError`` when the input is not one mapping with its full id, or
  ///   when the use case breaks a rule.
  func check(_ input: AuthoredInput) throws(UseCaseEditingError) -> CheckedUseCase
}
