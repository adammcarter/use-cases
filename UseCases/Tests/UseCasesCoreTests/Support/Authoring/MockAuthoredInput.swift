@testable import UseCasesCore

/// An authored input reader that returns the input the test decides, whatever the source.
struct MockAuthoredInput: AuthoredInputReading {
  private let outcome: Result<AuthoredInput, AuthoredInputError>

  init(_ input: AuthoredInput) {
    outcome = .success(input)
  }

  init(failing error: AuthoredInputError) {
    outcome = .failure(error)
  }

  func read(_: AuthoredInputSource) throws(AuthoredInputError) -> AuthoredInput {
    try outcome.get()
  }
}
