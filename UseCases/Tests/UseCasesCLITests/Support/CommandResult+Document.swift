import Foundation
@testable import UseCasesCLI

extension CommandResult {
  /// The one JSON document on stdout.
  func document() throws -> JSONValue {
    try JSONDecoder().decode(
      JSONValue.self,
      from: Data(standardOutput.utf8),
    )
  }
}
