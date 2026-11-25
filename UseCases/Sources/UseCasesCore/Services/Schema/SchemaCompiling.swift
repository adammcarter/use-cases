/// Turns a JSON Schema, read as an ``AuthoredValue``, into a program the checker can run.
protocol SchemaCompiling: Sendable {
  /// - Parameters:
  ///   - schema: The schema to compile.
  ///   - documents: The other schemas it may refer to as `<file>#/$defs/<name>`, by file name.
  ///   - unknownMembers: Whether `additionalProperties: false` refuses a member or ignores it.
  func compile(
    _ schema: AuthoredValue,
    documents: [String: AuthoredValue],
    unknownMembers: UnknownMembers,
  ) throws(SchemaCompilerError) -> SchemaProgram
}
