import Foundation
import MCP

/// Reads the frames a host sends, and swaps the arguments of each call for a key to them (see
/// ``ToolCallArguments``). A frame that holds no call is passed on as it came.
struct ToolFrameReader: ToolFrameReading {
  private let arguments: any ToolCallArgumentHolding

  init(arguments: any ToolCallArgumentHolding) {
    self.arguments = arguments
  }

  func frame(for frame: Data) async -> Data {
    guard
      let message = try? JSONDecoder().decode(PlainJSON.self, from: frame).value,
      let swapped = await swapping(message)
    else {
      return frame
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    return (try? encoder.encode(swapped)) ?? frame
  }

  /// `message` with the arguments of its calls swapped, or `nil` if it holds none.
  private func swapping(_ message: Value) async -> Value? {
    if case let .array(items) = message {
      var swappedItems: [Value] = []
      var isSwapped = false

      for item in items {
        if let swapped = await swapping(item) {
          swappedItems.append(swapped)
          isSwapped = true
        } else {
          swappedItems.append(item)
        }
      }

      return isSwapped ? .array(swappedItems) : nil
    }

    guard
      case var .object(members) = message,
      members["method"] == .string(CallTool.name),
      case var .object(parameters)? = members["params"],
      let given = parameters["arguments"],
      case .object = given
    else {
      return nil
    }

    let key = await arguments.hold(given)
    parameters["arguments"] = .object([ToolCallArguments.keyMember: .string(key)])
    members["params"] = .object(parameters)

    return .object(members)
  }
}
