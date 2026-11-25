import UseCasesCore

/// Why a workspace could not be read for links: it did not load, or its links are a problem.
enum LinkedWorkspaceError: Error, Equatable {
  /// The workspace did not load (chapter 09 §26).
  case notLoaded(WorkspaceLoadingError)

  /// A link transformer gave no usable answer, so the links are unknown (chapter 10 §14).
  case transformerFailed(TransformerLinkingError)

  /// The workspace loaded and its links make it INVALID (chapter 08 "Diagnostics"). Each problem
  /// is one line, in report order.
  case invalidLinks(problems: [String])

  /// How a refusal is told to a script (chapter 16 §5); `nil` for a cancellation, which is not a
  /// refusal.
  var refusalKind: RefusalKind? {
    switch self {
    case let .notLoaded(error):
      error.refusalKind
    case .transformerFailed(.cancelled):
      nil
    case .transformerFailed, .invalidLinks:
      .invalid
    }
  }

  /// The refusal as the text a person reads: one line per problem.
  var message: String {
    switch self {
    case let .notLoaded(error):
      error.message
    case let .transformerFailed(error):
      error.message
    case let .invalidLinks(problems):
      problems.joined(separator: "\n")
    }
  }
}
