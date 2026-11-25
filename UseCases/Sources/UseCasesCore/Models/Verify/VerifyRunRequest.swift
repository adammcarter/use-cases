/// What `use-cases verify --run` was asked (chapter 16 §2).
public struct VerifyRunRequest: Equatable, Sendable {
  /// The validations to run, from `--only`; empty runs every validation of the bridge settings.
  public let only: [String]

  /// Makes a request.
  public init(only: [String]) {
    self.only = only
  }
}
