import UseCasesCore

/// A links provider that answers the way the test says, whatever the workspace holds.
public struct MockTransformerLinks: TransformerLinkProviding {
  private let answer: @Sendable (LoadedWorkspace) -> Result<
    TransformedLinks,
    TransformerLinkingError,
  >

  /// Returns no links and says nothing, as a workspace without link transformers does.
  public static let none = MockTransformerLinks { _ in
    .success(.none)
  }

  /// Fails with this error.
  public static func failing(_ error: TransformerLinkingError) -> MockTransformerLinks {
    MockTransformerLinks { _ in
      .failure(error)
    }
  }

  /// `answer` is asked with the workspace each time.
  public init(
    answer: @escaping @Sendable (LoadedWorkspace) -> Result<
      TransformedLinks,
      TransformerLinkingError,
    >,
  ) {
    self.answer = answer
  }

  public func links(for workspace: LoadedWorkspace) async throws(TransformerLinkingError)
    -> TransformedLinks
  {
    try answer(workspace).get()
  }
}
