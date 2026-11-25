import Foundation
@testable import UseCasesCore

extension FileChange {
  /// The bytes of the change as the text a test reads.
  var text: String {
    String(bytes: bytes, encoding: .utf8) ?? ""
  }
}
