@testable import UseCasesCore

/// A standard input that holds a text the test decides, or is not text at all.
struct MockStandardInput: StandardInputReading {
  private let outcome: Result<String, AuthoredInputError>

  init(_ text: String) {
    outcome = .success(text)
  }

  init(failing error: AuthoredInputError) {
    outcome = .failure(error)
  }

  func readText() throws(AuthoredInputError) -> String {
    try outcome.get()
  }
}
