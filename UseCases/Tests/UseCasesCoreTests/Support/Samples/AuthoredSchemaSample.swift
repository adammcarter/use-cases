import Testing
@testable import UseCasesCore

/// One document and the verdict its schema gives it.
struct AuthoredSchemaSample: Sendable, CustomTestStringConvertible {
  let name: String
  let schema: AuthoredSchema
  let json: String
  let isValid: Bool

  var testDescription: String {
    "\(schema.rawValue) \(isValid ? "valid" : "invalid"): \(name)"
  }

  static func valid(
    _ name: String,
    _ schema: AuthoredSchema,
    _ json: String,
  ) -> AuthoredSchemaSample {
    AuthoredSchemaSample(
      name: name,
      schema: schema,
      json: json,
      isValid: true,
    )
  }

  static func invalid(
    _ name: String,
    _ schema: AuthoredSchema,
    _ json: String,
  ) -> AuthoredSchemaSample {
    AuthoredSchemaSample(
      name: name,
      schema: schema,
      json: json,
      isValid: false,
    )
  }
}
