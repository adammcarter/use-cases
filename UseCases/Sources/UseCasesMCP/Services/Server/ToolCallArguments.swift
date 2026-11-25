import Foundation
import MCP

/// The arguments of the calls on their way in, exactly as the host wrote them.
///
/// The SDK reads a string that looks like a data URL as binary data, and writes it back out as
/// base64: `data: retention, deletion and export` would come out as something else. So the
/// transport reads each call's arguments itself, keeps them here, and hands the SDK a key to
/// them in their place; the handler gets them back with the key.
actor ToolCallArguments: ToolCallArgumentHolding {
  /// The one member of the arguments the SDK is given in their place.
  static let keyMember = "use-cases/arguments"

  private var held: [String: Value] = [:]

  func hold(_ arguments: Value) -> String {
    let key = UUID().uuidString
    held[key] = arguments

    return key
  }

  /// The arguments a call was sent with: the ones kept for it when what the SDK read is a key,
  /// and what the SDK read when it is not. Each is given once.
  func arguments(read: [String: Value]?) -> [String: Value]? {
    guard
      let read,
      read.count == 1,
      case let .string(key)? = read[Self.keyMember],
      let arguments = held.removeValue(forKey: key)
    else {
      return read
    }

    return arguments.objectValue
  }
}
