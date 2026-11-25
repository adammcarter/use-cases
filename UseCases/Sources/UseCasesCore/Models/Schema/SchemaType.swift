/// A JSON Schema `type`, as the schemas name it.
enum SchemaType: String, CaseIterable, Sendable {
  case object
  case array
  case string
  case number
  case integer
  case boolean
  case null

  /// Whether a value is of this type. As Draft 2020-12 says, an `integer` is any number with no
  /// fractional part, so a number written `1.0` is one.
  func matches(_ value: AuthoredValue) -> Bool {
    switch (self, value) {
    case (.object, .object), (.array, .array), (.string, .string),
         (.boolean, .boolean), (.null, .null):
      true
    case (.number, .integer), (.number, .number), (.integer, .integer):
      true
    case let (.integer, .number(number)):
      number.isFinite && number.rounded() == number
    default:
      false
    }
  }
}
