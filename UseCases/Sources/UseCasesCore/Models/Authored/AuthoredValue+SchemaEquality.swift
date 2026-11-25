extension AuthoredValue {
  /// Whether two values are the same JSON value, as `const`, `enum` and `uniqueItems` mean it:
  /// numbers compare by value, an object's members compare whatever their order, and text
  /// compares scalar by scalar.
  func isSchemaEqual(to other: AuthoredValue) -> Bool {
    switch (self, other) {
    case let (.string(left), .string(right)):
      left.unicodeScalars.elementsEqual(right.unicodeScalars)
    case let (.boolean(left), .boolean(right)):
      left == right
    case (.null, .null):
      true
    case let (.array(left), .array(right)):
      left.count == right.count && zip(left, right).allSatisfy {
        $0.isSchemaEqual(to: $1)
      }
    case let (.object(left), .object(right)):
      Self.areEqual(members: left, members: right)
    default:
      isSchemaEqualNumber(to: other)
    }
  }

  /// Whether the value is one of `options`, by ``isSchemaEqual(to:)``.
  func isAmong(_ options: [AuthoredValue]) -> Bool {
    for option in options where option.isSchemaEqual(to: self) {
      return true
    }

    return false
  }

  private func isSchemaEqualNumber(to other: AuthoredValue) -> Bool {
    switch (self, other) {
    case let (.integer(left), .integer(right)):
      left == right
    case let (.number(left), .number(right)):
      left == right
    case let (.integer(integer), .number(number)), let (.number(number), .integer(integer)):
      Int(exactly: number) == integer
    default:
      false
    }
  }

  private static func areEqual(
    members left: [AuthoredMember],
    members right: [AuthoredMember],
  ) -> Bool {
    guard left.count == right.count else {
      return false
    }

    return left.allSatisfy { member in
      right.contains { candidate in
        candidate.key.unicodeScalars.elementsEqual(member.key.unicodeScalars)
          && candidate.value.isSchemaEqual(to: member.value)
      }
    }
  }
}
