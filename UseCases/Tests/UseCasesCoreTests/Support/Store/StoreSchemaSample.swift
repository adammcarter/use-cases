import Testing
@testable import UseCasesCore

/// One store document and the verdict its schema gives it.
struct StoreSchemaSample: Sendable, CustomTestStringConvertible {
  let name: String
  let schema: StoreSchema
  let json: String
  let isValid: Bool

  var testDescription: String {
    "\(schema.rawValue) \(isValid ? "valid" : "invalid"): \(name)"
  }

  static func valid(
    _ name: String,
    _ schema: StoreSchema,
    _ document: JSONMembers,
  ) -> StoreSchemaSample {
    StoreSchemaSample(
      name: name,
      schema: schema,
      json: document.json,
      isValid: true,
    )
  }

  static func invalid(
    _ name: String,
    _ schema: StoreSchema,
    _ document: JSONMembers,
  ) -> StoreSchemaSample {
    StoreSchemaSample(
      name: name,
      schema: schema,
      json: document.json,
      isValid: false,
    )
  }
}
