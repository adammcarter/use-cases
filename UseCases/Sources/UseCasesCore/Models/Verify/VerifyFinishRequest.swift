/// What `use-cases verify --finish` was asked (chapter 16 §2).
public struct VerifyFinishRequest: Equatable, Sendable {
  /// The run to finish, from `--run-id`; `nil` finishes the only run `--start` left open.
  public let runIdentifier: String?

  /// Makes a request.
  public init(runIdentifier: String?) {
    self.runIdentifier = runIdentifier
  }
}
