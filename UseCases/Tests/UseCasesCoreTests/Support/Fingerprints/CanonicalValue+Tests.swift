@testable import UseCasesCore

extension CanonicalValue {
  /// The canonical bytes as text, for a value that must encode.
  func canonicalText() throws -> String {
    try CanonicalJSONEncoder().encode(self).utf8Text
  }
}
