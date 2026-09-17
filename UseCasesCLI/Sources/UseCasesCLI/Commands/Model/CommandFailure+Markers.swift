import UseCasesCore

extension CommandFailure {
  /// A marker command core's throw, coded as the TypeScript's throw is: node's
  /// errno code for a file, the matrix loader's own code, and `internal_error`
  /// for the plain `Error`s git, canonical JSON, signing and the verifier
  /// spawn raise there.
  init(_ error: MarkerCommandError) {
    switch error {
    case let .fileAccess(failure), let .verificationContextHash(.fileAccess(failure)):
      self.init(failure)
    case let .useCaseMatrix(failure):
      self.init(failure)
    default:
      self.init(code: Self.internalErrorCode, message: error.message)
    }
  }
}
