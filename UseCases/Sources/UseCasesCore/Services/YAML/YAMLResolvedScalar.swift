/// What a plain scalar means in one YAML version.
enum YAMLResolvedScalar: Equatable, Sendable {
  case null
  case boolean(Bool)
  case integer(YAMLInteger)
  case number(Double)

  /// A base-60 number such as `1:30`, which only YAML 1.1 reads as a number.
  case sexagesimal

  /// A date or a date and time, which only YAML 1.1 reads as one.
  case timestamp

  /// The `<<` key, which only YAML 1.1 reads as a merge.
  case mergeKey

  /// The `=` key, which only YAML 1.1 reads as the value key.
  case valueKey
  case text

  /// How a message names this reading.
  var phrase: String {
    switch self {
    case .null: "null"
    case let .boolean(value): "the boolean \(value)"
    case let .integer(.exact(value)): "the integer \(value)"
    case .integer(.tooLarge): "an integer too big for 64 bits"
    case let .number(value): "the number \(value)"
    case .sexagesimal: "a base-60 number"
    case .timestamp: "a date or time"
    case .mergeKey: "the merge key"
    case .valueKey: "the value key"
    case .text: "text"
    }
  }

  /// Two readings agree when they type a scalar the same way and give it the same value.
  func agrees(with other: YAMLResolvedScalar) -> Bool {
    if case let .number(left) = self, case let .number(right) = other {
      return left == right || (left.isNaN && right.isNaN)
    }

    return self == other
  }
}
