import UseCasesCore

/// An answerer that gives every request what the test decides.
public struct MockDocsAnswering: DocsAnswering {
  private let outcome: Result<DocsAnswer, DocsError>

  /// Answers every request with `answer`.
  public init(answering answer: DocsAnswer) {
    outcome = .success(answer)
  }

  /// Refuses every request with `error`.
  public init(refusing error: DocsError) {
    outcome = .failure(error)
  }

  public func answer(_: DocsRequest) throws(DocsError) -> DocsAnswer {
    try outcome.get()
  }
}
