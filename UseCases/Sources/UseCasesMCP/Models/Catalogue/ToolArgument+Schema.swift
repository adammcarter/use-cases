import MCP

extension ToolArgument {
  /// The argument as a property of the tool's input schema.
  var schema: Value {
    var members: [String: Value] = [
      "description": .string(description),
    ]

    switch type {
    case .string:
      members["type"] = .string("string")
    case .integer:
      members["type"] = .string("integer")
    case .boolean:
      members["type"] = .string("boolean")
    case .stringList:
      members["type"] = .string("array")
      members["items"] = .object(Self.items(of: allowedValues))
    case .object:
      members["type"] = .string("object")
    case .objectList:
      members["type"] = .string("array")
      members["items"] = .object(["type": .string("object")])
    }

    if !allowedValues.isEmpty, type != .stringList {
      members["enum"] = .array(allowedValues.map(Value.string))
    }

    if let range {
      members["minimum"] = .int(range.lowerBound)
      members["maximum"] = .int(range.upperBound)
    }

    return .object(members)
  }

  /// The schema of each item of a list of strings, which names the values it takes if it does.
  private static func items(of allowedValues: [String]) -> [String: Value] {
    var items: [String: Value] = ["type": .string("string")]

    if !allowedValues.isEmpty {
      items["enum"] = .array(allowedValues.map(Value.string))
    }

    return items
  }
}
