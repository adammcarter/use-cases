/// A JavaScript `Set` of parsed values: membership by `SameValueZero`, so
/// strings by code unit and numbers by value, while two parsed objects or
/// arrays are never the same member.
struct JavaScriptValueSet {
  private var members: [JSONValue?] = []

  var count: Int {
    members.count
  }

  mutating func insert(_ value: JSONValue?) {
    if !contains(value) {
      members.append(value)
    }
  }

  mutating func remove(_ value: JSONValue?) {
    let index = members.firstIndex { member in
      Self.sameValueZero(member, value)
    }
    if let index {
      members.remove(at: index)
    }
  }

  func contains(_ value: JSONValue?) -> Bool {
    members.contains { member in
      Self.sameValueZero(member, value)
    }
  }

  private static func sameValueZero(
    _ left: JSONValue?,
    _ right: JSONValue?,
  ) -> Bool {
    switch (left, right) {
    case (.none, .none), (.null, .null):
      true
    case let (.bool(leftFlag), .bool(rightFlag)):
      leftFlag == rightFlag
    case let (.number(leftNumber), .number(rightNumber)):
      leftNumber == rightNumber || (leftNumber.isNaN && rightNumber.isNaN)
    case let (.string(leftText), .string(rightText)):
      JavaScriptString.identical(leftText, rightText)
    default:
      false
    }
  }
}
