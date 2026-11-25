import Testing
@testable import UseCasesCore

/// Reads the JSON text of a test and requires that its schema accepts it, so a test of a model
/// only ever meets values the loader hands it.
func checked(
  _ json: String,
  against schema: AuthoredSchema,
) throws -> AuthoredValue {
  let value = try authored(json)
  let failures = try BundledSchemaLoader().loadChecker(for: schema).check(value)

  try #require(
    failures.isEmpty,
    "the sample breaks its schema: \(failures.map(\.description))",
  )

  return value
}

/// A piece of text as JSON writes it, for text with nothing to escape.
func jsonString(_ text: String) -> String {
  "\"" + text + "\""
}

/// The path of a file as a diagnostic names it.
func workspacePath(_ text: String) throws -> WorkspacePath {
  try WorkspacePath(validating: text)
}
