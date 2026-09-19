import Testing
@testable import UseCasesCore

/// The schema and algorithm identifiers are written into registry events and
/// ledgers, so each one must survive byte for byte.
struct MarkerConstantsTests {
  @Test
  func `every identifier matches the TypeScript export`() throws {
    let expected = try MarkersFixtures.constants()
    let actual: [(String, String)] = [
      ("MARKER_SCHEMA_ID", MarkerConstants.markerSchemaIdentifier),
      ("BINDING_REGISTRY_SCHEMA_ID", MarkerConstants.bindingRegistrySchemaIdentifier),
      ("EVIDENCE_SCHEMA_ID", MarkerConstants.evidenceSchemaIdentifier),
      ("STATUS_SCHEMA_ID", MarkerConstants.statusSchemaIdentifier),
      ("SPAN_CANON_ID", MarkerConstants.spanCanonicalizerIdentifier),
      ("EXPLICIT_RECOGNIZER_ID", MarkerConstants.explicitRecognizerIdentifier),
      ("SWIFT_FUNC_RECOGNIZER_ID", MarkerConstants.swiftFunctionRecognizerIdentifier),
      ("BINDING_SET_HASH_ID", MarkerConstants.bindingSetHashIdentifier),
      ("ROW_HASH_ID", MarkerConstants.rowHashIdentifier),
    ]

    #expect(expected.count == actual.count)
    for (key, value) in actual {
      #expect(expected[key]?.stringValue == value, "\(key)")
    }
  }
}
