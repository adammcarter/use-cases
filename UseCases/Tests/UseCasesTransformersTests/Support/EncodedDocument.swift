import Foundation
import Testing

/// The JSON document an encodable value is written as, read back for the tests.
func document(of value: some Encodable) throws -> [String: Any] {
  let encoder = JSONEncoder()

  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

  let data = try encoder.encode(value)

  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
