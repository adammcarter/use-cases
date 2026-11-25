import UseCasesCore

/// A shower that answers every id with what the test decides.
public struct MockUseCaseShowing: UseCaseShowing {
  private let outcome: Result<ShownUseCase, UseCaseShowingError>

  /// Shows `useCase` for any id.
  public init(shows useCase: ShownUseCase) {
    outcome = .success(useCase)
  }

  /// Refuses any id with `error`.
  public init(refusing error: UseCaseShowingError) {
    outcome = .failure(error)
  }

  public func show(
    _: String,
    in _: LoadedWorkspace,
  ) throws(UseCaseShowingError) -> ShownUseCase {
    try outcome.get()
  }
}
