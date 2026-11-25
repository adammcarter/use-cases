/// A schema keyword whose check can fail. Declaration order is the order failures at the same
/// place are listed in.
enum SchemaKeyword: String, CaseIterable, Comparable, Sendable {
  case type
  case const
  case enumeration = "enum"
  case format
  case pattern
  case minLength
  case maxLength
  case minimum
  case maximum
  case required
  case dependentRequired
  case additionalProperties
  case propertyNames
  case minItems
  case maxItems
  case uniqueItems
  case anyOf
  case oneOf
  case not

  /// A `false` schema, which nothing satisfies.
  case falseSchema = "false"

  static func < (
    lhs: SchemaKeyword,
    rhs: SchemaKeyword,
  ) -> Bool {
    let order = allCases
    guard
      let left = order.firstIndex(of: lhs),
      let right = order.firstIndex(of: rhs)
    else {
      return false
    }

    return left < right
  }
}
