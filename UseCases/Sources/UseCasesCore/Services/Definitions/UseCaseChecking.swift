/// The checks on one use case that need nothing outside its file (chapter 02 "INVALID",
/// chapter 06 "Coverage").
protocol UseCaseChecking: Sendable {
  /// Every problem in the use case: scenarios or routes that share an id, and routes that cover
  /// a scenario the use case does not have. Empty when there is none.
  func check(
    _ useCase: UseCaseDefinition,
    file: WorkspacePath,
  ) -> [Diagnostic]
}
