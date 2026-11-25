/// Checks a JSON document against one schema.
public protocol JSONSchemaValidating: Sendable {
  /// Every way the document breaks the schema, sorted by path and then by keyword: the same list
  /// every time. Empty when it satisfies the schema.
  func problems(in documentText: String) -> [JSONSchemaProblem]
}
