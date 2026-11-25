/// One version of YAML's rules for typing a plain scalar.
protocol YAMLSchemaResolving: Sendable {
  func resolve(_ text: String) -> YAMLResolvedScalar
}
