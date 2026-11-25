/// Why a plain scalar must be quoted.
enum YAMLUnquotedProblem: Equatable, Sendable {
  /// YAML 1.1 and YAML 1.2 read it differently.
  case readDifferently(yaml11: YAMLResolvedScalar, yaml12: YAMLResolvedScalar)

  /// It is an integer that does not fit in an `Int`.
  case integerTooLarge

  /// It is a number JSON cannot hold: infinity, not-a-number, or a float that overflows.
  case notJSONNumber

  /// It holds a `?` inside a list or mapping written on one line, where YAML readers disagree
  /// about it.
  case questionMarkInFlow

  /// It is a key, and a plain key must read as text.
  case keyNotText(AuthoredValue)

  var message: String {
    switch self {
    case let .readDifferently(yaml11, yaml12):
      "reads as \(yaml11.phrase) in YAML 1.1 and as \(yaml12.phrase) in YAML 1.2; quote it"
    case .integerTooLarge:
      "is an integer too big to read exactly; quote it if it is text"
    case .notJSONNumber:
      "is a number JSON cannot hold; quote it"
    case .questionMarkInFlow:
      "has a '?' in a list or mapping written on one line, which YAML readers read differently; "
        + "quote it"
    case let .keyNotText(value):
      "is a plain key that reads as \(Self.phrase(of: value)), not text; quote it"
    }
  }

  private static func phrase(of value: AuthoredValue) -> String {
    switch value {
    case .null: "null"
    case .boolean: "a boolean"
    case .integer: "an integer"
    case .number: "a number"
    default: "something other than text"
    }
  }
}
