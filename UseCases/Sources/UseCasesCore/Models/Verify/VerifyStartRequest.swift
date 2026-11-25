/// What `use-cases verify --start` was asked (chapter 16 §2).
public struct VerifyStartRequest: Equatable, Sendable {
  /// The validations to read, from `--only`; empty reads every validation of the bridge settings.
  public let only: [String]

  /// Makes a request.
  public init(only: [String]) {
    self.only = only
  }
}
