import Foundation
import MCP

struct JSONValueWriter: JSONValueWriting {
  func text(of value: Value) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    guard let data = try? encoder.encode(value) else {
      return nil
    }

    return String(
      data: data,
      encoding: .utf8,
    )
  }
}
