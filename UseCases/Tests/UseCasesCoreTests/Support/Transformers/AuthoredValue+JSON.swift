@testable import UseCasesCore

extension AuthoredValue {
  /// The value a JSON text reads as; the test fails on text that is not JSON.
  static func json(_ text: String) throws -> AuthoredValue {
    try JSONReader().read(text)
  }
}
