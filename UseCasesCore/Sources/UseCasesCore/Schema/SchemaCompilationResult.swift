/// The outcome of loading and resolving every published schema.
public struct SchemaCompilationResult: Sendable, Equatable {
  public let isValid: Bool
  public let schemaCount: Int
  public let diagnostics: [Diagnostic]

  public init(
    isValid: Bool,
    schemaCount: Int,
    diagnostics: [Diagnostic],
  ) {
    self.isValid = isValid
    self.schemaCount = schemaCount
    self.diagnostics = diagnostics
  }
}
