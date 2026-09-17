import Testing
@testable import UseCasesCore

/// The marker validators run AJV (`allErrors`, `strict`) over the three marker
/// schemas. Their messages are embedded verbatim in REGISTRY_SCHEMA_INVALID and
/// EVIDENCE_SCHEMA_INVALID diagnostics, so the text and its order are pinned.
struct MarkerSchemaValidationTests {
  @Test
  func `validation results match the TypeScript for every schema`() throws {
    for entry in try MarkersLedgerFixtures.section("schema_validation") {
      let value = try MarkersLedgerFixtures.parsed(entry, "value_text")
      let schemaIdentifier = try MarkersLedgerFixtures.string(entry, "schema")
      let result = MarkerSchemaValidation.validate(schemaIdentifier: schemaIdentifier, value: value)
      let expected = try #require(entry["result"])

      #expect(
        MarkersLedgerFixtures.wire(result.jsonValue) == MarkersLedgerFixtures.wire(expected),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `the named validators pick their own schema`() throws {
    let registryCase = try MarkersLedgerFixtures.entry("registry_valid", in: "schema_validation")
    let proofCase = try MarkersLedgerFixtures.entry("proof_valid", in: "schema_validation")
    let registryEvent = try MarkersLedgerFixtures.parsed(registryCase, "value_text")
    let proofEvent = try MarkersLedgerFixtures.parsed(proofCase, "value_text")

    #expect(MarkerSchemaValidation.validateBindingRegistryEvent(registryEvent).isValid)
    #expect(MarkerSchemaValidation.validateBindingRegistryEvent(proofEvent).isValid == false)
    #expect(MarkerSchemaValidation.validateProofEvent(proofEvent).isValid)
    #expect(MarkerSchemaValidation.validateProofEvent(registryEvent).isValid == false)
    #expect(MarkerSchemaValidation.validateFreshnessStatus(proofEvent).isValid == false)
  }
}
