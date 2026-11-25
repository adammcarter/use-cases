/// Checks values against a JSON Schema (Draft 2020-12) written with exactly the keywords the
/// four authored schemas use.
struct SchemaChecker: SchemaChecking {
  private let program: SchemaProgram

  /// Compiles the schema. A keyword the checker does not support, or a value a keyword cannot
  /// take, is refused here, never skipped.
  ///
  /// - Parameters:
  ///   - schema: The schema to check against.
  ///   - documents: The other schemas it refers to as `<file>#/$defs/<name>`, by file name.
  ///   - unknownMembers: Whether a member the schema does not list breaks it.
  ///   - compiler: What compiles them.
  init(
    schema: AuthoredValue,
    documents: [String: AuthoredValue] = [:],
    unknownMembers: UnknownMembers = .refuse,
    compiler: any SchemaCompiling = SchemaCompiler(),
  ) throws(SchemaCompilerError) {
    program = try compiler.compile(
      schema,
      documents: documents,
      unknownMembers: unknownMembers,
    )
  }

  func check(_ value: AuthoredValue) -> [SchemaFailure] {
    let evaluation = SchemaEvaluation(program: program)

    return Set(evaluation.failures(
      of: value,
      at: [],
      against: program.root,
    )).sorted()
  }
}
