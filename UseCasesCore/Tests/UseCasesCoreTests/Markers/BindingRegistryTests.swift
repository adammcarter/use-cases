import Testing
@testable import UseCasesCore

/// The append-only binding registry (registry.ts): read, validate against the
/// spec 4.3 rules, and materialize, with frozen error codes.
struct BindingRegistryTests {
  private func materializedWire(_ registry: MaterializedRegistry) -> JSONValue {
    .object(JSONObject([
      ("row_to_slugs", .array(registry.rowToSlugs.map { entry in
        .array([.string(entry.rowIdentifier), .array(entry.bindingSlugs.map(JSONValue.string))])
      })),
      ("slug_to_row", .array(registry.slugToRow.map { entry in
        .array([.string(entry.bindingSlug), .string(entry.rowIdentifier)])
      })),
    ]))
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.registryCaseNames)
  func `a registry reads, validates and materializes exactly as the TypeScript does`(
    caseName: String,
  ) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "registry")
    let text = try MarkersLedgerFixtures.string(entry, "text")
    let rows = try Set(MarkersLedgerFixtures.strings(entry, "rows"))

    let read = BindingRegistry.read(text)
    let result = BindingRegistry.validate(text: text, yamlRowIdentifiers: rows)

    #expect(try LedgerComparison.wire(read.jsonValue) == LedgerComparison
      .wire(#require(entry["read"])))
    #expect(.bool(result.isValid) == entry["ok"])
    #expect(try LedgerComparison.wire(.array(result.errors.map(\.jsonValue)))
      == LedgerComparison.wire(#require(entry["errors"])))
    #expect(try MarkersLedgerFixtures.wire(.array(result.events.map(\.json)))
      == MarkersLedgerFixtures.wire(#require(entry["events"])))
    #expect(try MarkersLedgerFixtures.wire(materializedWire(result.registry))
      == MarkersLedgerFixtures.wire(#require(entry["registry"])))
    #expect(try MarkersLedgerFixtures
      .wire(materializedWire(BindingRegistry.materialize(result.events)))
      == MarkersLedgerFixtures.wire(#require(entry["rematerialized"])))
  }

  @Test
  func `the registry error codes are frozen`() {
    #expect(RegistryErrorCode.allCases.map(\.rawValue) == [
      "JSON_PARSE_ERROR",
      "REGISTRY_SCHEMA_INVALID",
      "SLUG_PREFIX_MISMATCH",
      "REGISTRY_ROW_MISSING",
      "DUPLICATE_REGISTRATION",
      "SLUG_ROW_CONFLICT",
      "RELEASE_WITHOUT_REGISTRATION",
    ])
  }

  @Test
  func `lookups answer from the materialized state`() throws {
    let entry = try MarkersLedgerFixtures.entry("many_slugs_per_row", in: "registry")
    let text = try MarkersLedgerFixtures.string(entry, "text")
    let registry = BindingRegistry.validate(text: text, yamlRowIdentifiers: []).registry

    #expect(registry.bindingSlugs(forRow: "checkout.apply_coupon")
      == ["checkout.apply_coupon#a", "checkout.apply_coupon"])
    #expect(registry.rowIdentifier(forSlug: "checkout.apply_coupon#a") == "checkout.apply_coupon")
    #expect(registry.rowIdentifier(forSlug: "checkout.apply_coupon#b") == nil)
    #expect(registry.bindingSlugs(forRow: "missing") == nil)
  }

  /// Only a registry built by hand can bind a slug to a row other than its own
  /// prefix; the marker is then unregistered for the row it names.
  @Test
  func `a slug bound to another row is an unregistered marker, as in the TypeScript`() throws {
    for entry in try MarkersLedgerFixtures.section("reconcile_hand_built") {
      var registry = MaterializedRegistry()
      for pair in try #require(entry["registry"]?.arrayValue) {
        let row = try #require(pair.arrayValue?.first?.stringValue)
        for slug in try #require(pair.arrayValue?.last?.arrayValue) {
          try registry.register(#require(slug.stringValue), to: row)
        }
      }
      let inputs = try #require(entry["files"]?.arrayValue).map { file in
        try ScanInput(
          filePath: MarkersLedgerFixtures.string(file, "file_path"),
          contents: MarkersLedgerFixtures.string(file, "contents"),
        )
      }

      let result = RegistryReconciliation.reconcile(
        registry: registry,
        scan: MarkerScanner.scanFiles(inputs),
      )

      #expect(try MarkersLedgerFixtures.wire(result.jsonValue)
        == MarkersLedgerFixtures.wire(#require(entry["result"])))
    }
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.reconcileCaseNames)
  func `reconciliation derives the TypeScript's sets`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "reconcile")
    let registryText = try MarkersLedgerFixtures.string(entry, "registry_text")
    let registry = BindingRegistry.validate(text: registryText, yamlRowIdentifiers: []).registry
    let inputs = try #require(entry["files"]?.arrayValue).map { file in
      try ScanInput(
        filePath: MarkersLedgerFixtures.string(file, "file_path"),
        contents: MarkersLedgerFixtures.string(file, "contents"),
      )
    }

    let result = RegistryReconciliation.reconcile(
      registry: registry,
      scan: MarkerScanner.scanFiles(inputs),
    )

    #expect(try MarkersLedgerFixtures.wire(result.jsonValue)
      == MarkersLedgerFixtures.wire(#require(entry["result"])))
  }
}
