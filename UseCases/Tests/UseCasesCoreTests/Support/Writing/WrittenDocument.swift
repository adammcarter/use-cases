import Testing
@testable import UseCasesCore

/// A document the store's writers print, read back the way a reader reads it and checked against
/// the bundled schema with the members of the schema only.
struct WrittenDocument {
  let value: AuthoredValue
  let failures: [SchemaFailure]

  init(
    _ document: StoreJSONValue,
    schema: StoreSchema,
  ) throws {
    let bytes = StoreJSONWriter().pretty(document)
    value = try JSONReader().read(bytes.utf8Text)
    failures = try BundledStoreSchemaLoader().loadChecker(for: schema).check(value)
  }

  var object: AuthoredObject {
    get throws {
      try AuthoredObject(value, at: "")
    }
  }
}
