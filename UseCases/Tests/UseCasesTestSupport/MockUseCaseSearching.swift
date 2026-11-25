import UseCasesCore

/// A searcher that answers every search with what the test decides.
public struct MockUseCaseSearching: UseCaseSearching {
  private let outcome: Result<SearchPage, UseCaseSearchError>

  /// Answers every search with `page`.
  public init(finding page: SearchPage) {
    outcome = .success(page)
  }

  /// Refuses every search with `error`.
  public init(refusing error: UseCaseSearchError) {
    outcome = .failure(error)
  }

  public func search(
    _: SearchPlan,
    in _: LoadedWorkspace,
    status _: WorkspaceStatus,
  ) throws(UseCaseSearchError) -> SearchPage {
    try outcome.get()
  }
}
