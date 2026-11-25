/// What `use-cases verify --abort` was asked (chapter 16 §2).
public struct VerifyAbortRequest: Equatable, Sendable {
  /// The run to close, from `--run-id`; `nil` closes the only run left open.
  public let runIdentifier: String?

  /// Makes a request.
  public init(runIdentifier: String?) {
    self.runIdentifier = runIdentifier
  }
}
