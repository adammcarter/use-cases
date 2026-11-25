import UseCasesCore

/// A loader that gives the guides a test decides, or fails as the test decides.
public struct MockGuideLoading: GuideLoading {
  private let outcome: Result<[Guide], GuideLoadingError>

  /// Gives `guides`.
  public init(guides: [Guide]) {
    outcome = .success(guides)
  }

  /// Fails with `error`.
  public init(failing error: GuideLoadingError) {
    outcome = .failure(error)
  }

  public func guides() throws(GuideLoadingError) -> [Guide] {
    try outcome.get()
  }
}
