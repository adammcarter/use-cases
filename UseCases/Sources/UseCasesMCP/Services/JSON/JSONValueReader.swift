import Foundation
import MCP

struct JSONValueReader: JSONValueReading {
  func value(of text: String) -> Value? {
    try? JSONDecoder().decode(
      PlainJSON.self,
      from: Data(text.utf8),
    ).value
  }
}
