/// Why a schema cannot be compiled. A `location` is the path through the schema to the
/// offending schema object, steps joined by `/`; empty for the schema itself.
enum SchemaCompilerError: Error, Equatable {
  /// A keyword the checker does not support. It is never skipped, or a typo would pass
  /// everything it was meant to refuse.
  case unknownKeyword(String, location: String)

  /// A keyword whose value is not the kind of value it takes.
  case invalidKeywordValue(String, location: String)

  /// Where a schema belongs there is neither an object nor a boolean.
  case notASchema(location: String)

  /// A `$ref` that is not `#/$defs/<name>` naming a definition.
  case unresolvedReference(String)

  /// A `pattern` that is not a regular expression.
  case invalidPattern(String, location: String)

  /// A `pattern` using syntax that ECMA-262 and Swift Regex read differently, such as `\d` or
  /// `(?i)`; only the syntax the bundled schemas use is supported.
  case unsupportedPattern(String, construct: String, location: String)

  /// A `format` the checker does not enforce.
  case unsupportedFormat(String, location: String)

  /// A `$schema` other than Draft 2020-12.
  case unsupportedDialect(String)
}
