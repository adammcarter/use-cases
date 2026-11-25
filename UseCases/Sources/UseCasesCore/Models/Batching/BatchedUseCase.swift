/// What became of one use case of a batch (chapter 16 §14).
public struct BatchedUseCase: Equatable, Sendable {
  /// The full id of the use case.
  public let identifier: String

  /// The definition file it is in, or was in, relative to the workspace root.
  public let file: String

  /// What was done to it: ``UseCaseChangeAction/removed``, ``UseCaseChangeAction/created``,
  /// ``UseCaseChangeAction/added``, ``UseCaseChangeAction/replaced`` or
  /// ``UseCaseChangeAction/unchanged``.
  public let action: UseCaseChangeAction
}
