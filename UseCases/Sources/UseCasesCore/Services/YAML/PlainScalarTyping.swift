/// Types a plain (unquoted) scalar for an authored file.
protocol PlainScalarTyping: Sendable {
  func type(of text: String) -> PlainScalarTyped
}

/// How a plain scalar was typed.
enum PlainScalarTyped: Equatable, Sendable {
  /// The value YAML 1.2's core schema gives it, which YAML 1.1 gives too.
  case value(AuthoredValue)

  /// The two YAML versions read it differently, so it must be quoted.
  case readDifferently(yaml11: YAMLResolvedScalar, yaml12: YAMLResolvedScalar)

  /// An integer that does not fit in an `Int`.
  case integerTooLarge

  /// A number JSON cannot hold: infinity, not-a-number, or a float that overflows.
  case notJSONNumber
}
