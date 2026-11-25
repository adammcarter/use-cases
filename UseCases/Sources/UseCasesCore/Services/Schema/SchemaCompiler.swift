/// Compiles the schemas of Use Cases: Draft 2020-12, for exactly the keywords the four authored
/// schemas use.
struct SchemaCompiler: SchemaCompiling {
  func compile(
    _ schema: AuthoredValue,
    documents: [String: AuthoredValue],
    unknownMembers: UnknownMembers,
  ) throws(SchemaCompilerError) -> SchemaProgram {
    var compilation = SchemaCompilation(
      documents: documents,
      unknownMembers: unknownMembers,
    )

    return try compilation.compile(schema)
  }
}
