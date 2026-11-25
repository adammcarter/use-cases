/// A use case sent to `save` that passed every check a definition file passes.
struct CheckedUseCase: Equatable, Sendable {
  /// The full id it was sent under.
  let identifier: UseCaseIdentifier

  /// The use case, with its own id as a file holds it: the last segment of the full one.
  let definition: UseCaseDefinition
}
