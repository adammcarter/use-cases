import MCP

extension Value {
  /// Whether this value, or any value inside it, is binary data. The SDK makes a string that
  /// looks like a data URL into data; an argument that holds some was not read as it was written.
  var holdsData: Bool {
    switch self {
    case .data:
      true
    case let .array(items):
      items.contains { item in
        item.holdsData
      }
    case let .object(members):
      members.values.contains { member in
        member.holdsData
      }
    default:
      false
    }
  }
}
