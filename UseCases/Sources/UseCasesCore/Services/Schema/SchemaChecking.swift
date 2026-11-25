/// Checks an authored value against one schema.
protocol SchemaChecking: Sendable {
  /// Every way the value breaks the schema, sorted by path and then by message: the same list
  /// every time. Empty when the value satisfies the schema.
  func check(_ value: AuthoredValue) -> [SchemaFailure]
}
