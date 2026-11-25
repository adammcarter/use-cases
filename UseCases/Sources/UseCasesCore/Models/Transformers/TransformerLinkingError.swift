/// Why the links of the link transformers are unknown (chapter 10 §14, chapter 09 §20.4): the
/// workspace cannot load until the transformer is fixed.
public enum TransformerLinkingError: Error, Equatable, Sendable {
  /// A transformer gave no usable answer, or returned a link that cannot be placed. The message
  /// names the transformer.
  case failed(message: String)

  /// The run was cancelled while a transformer ran, and the transformer was stopped.
  case cancelled

  /// The error as the text a person reads.
  public var message: String {
    switch self {
    case let .failed(message):
      message
    case .cancelled:
      "cancelled"
    }
  }

  /// The public face of an internal error.
  init(_ error: TransformerError) {
    switch error {
    case .cancelled:
      self = .cancelled
    default:
      self = .failed(message: error.description)
    }
  }
}
