/// The outcome of reading a YAML document into JSON.
public struct ParsedYamlResult: Sendable, Equatable {
  public let isValid: Bool
  public let value: JSONValue?
  public let diagnostics: [Diagnostic]

  public init(
    isValid: Bool,
    value: JSONValue?,
    diagnostics: [Diagnostic],
  ) {
    self.isValid = isValid
    self.value = value
    self.diagnostics = diagnostics
  }
}
