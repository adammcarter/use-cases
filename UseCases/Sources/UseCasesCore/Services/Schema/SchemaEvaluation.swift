/// One check of a value: runs a compiled schema over it and collects what fails.
struct SchemaEvaluation {
  let program: SchemaProgram
  let patterns: [ExactText: Regex<AnyRegexOutput>]

  init(program: SchemaProgram) {
    self.program = program

    var patterns: [ExactText: Regex<AnyRegexOutput>] = [:]
    for node in program.nodes {
      if let source = node.pattern, let regex = SchemaPattern(source: source).makeRegex() {
        patterns[ExactText(source)] = regex
      }
    }
    self.patterns = patterns
  }

  /// Every failure of `value`, found at `path`, against the schema held by node `index`.
  func failures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    against index: Int,
  ) -> [SchemaFailure] {
    let node = program.nodes[index]
    if node.rejectsEverything {
      return [failure(
        path,
        .falseSchema,
        "\(value.schemaDescription) is not allowed",
      )]
    }

    var failures: [SchemaFailure] = []
    failures += typeFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += valueFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += stringFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += numberFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += objectFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += arrayFailures(
      of: value,
      at: path,
      node: node,
    )
    failures += combinatorFailures(
      of: value,
      at: path,
      node: node,
    )

    return failures
  }

  /// Whether `value` satisfies the schema held by node `index`.
  func isValid(
    _ value: AuthoredValue,
    against index: Int,
  ) -> Bool {
    failures(
      of: value,
      at: [],
      against: index,
    ).isEmpty
  }

  func failure(
    _ path: [SchemaPathStep],
    _ keyword: SchemaKeyword,
    _ message: String,
    members: [String] = [],
  ) -> SchemaFailure {
    SchemaFailure(
      path: path,
      keyword: keyword,
      message: message,
      members: members,
    )
  }
}
