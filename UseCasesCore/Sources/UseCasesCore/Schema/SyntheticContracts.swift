/// Validates the schemas that have no fixture file against representative
/// samples, so "every public schema is validated" stays true.
///
/// The five Phase 1 gap schemas document in-code and trust-engine shapes, and
/// the result envelopes are produced rather than authored; both are covered here
/// instead of by a file on disk. The samples are the TypeScript's own, character
/// for character, so a schema that drifts away from the shape the code produces
/// fails here first.
public enum SyntheticContracts {
  public static func validateCommonContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    validateEnvelopeContracts(
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
    validateMatrixContracts(
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
    validateEvidenceContracts(
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
    validateShowcaseContracts(
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
    validateTrustContracts(
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  /// `common` and the CLI envelope itself.
  private static func validateEnvelopeContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    check(
      "common.schema.json",
      sample: #"{"schema_version":1}"#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    let envelope = CliResult.make(
      command: "schema.synthetic",
      data: .object(JSONObject()),
    ).jsonValue()
    check(
      "cli-result.schema.json",
      value: envelope,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  /// The three matrix result envelopes.
  private static func validateMatrixContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    check(
      "matrix-validation-result.schema.json",
      sample: #"""
      {"schema_version":1,"complete":true,"valid":true,"integrity":{"state":"clean",\#
      "populated":false,"blocking_diagnostic_count":0},"files":[],"counts":\#
      {"files_discovered":0,"files_loaded":0,"files_excluded":0,"use_case_candidates":0,\#
      "use_cases_addressable":0,"use_cases_ambiguous":0,"use_cases_structurally_clean":0,\#
      "broken_references":0},"ambiguous_ids":[]}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    check(
      "matrix-list-result.schema.json",
      sample: #"""
      {"schema_version":1,"complete":true,"integrity":{"state":"clean","populated":false,\#
      "blocking_diagnostic_count":0},"use_cases":[],"counts":{"returned":0,\#
      "total_addressable":0}}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    check(
      "matrix-mutation-result.schema.json",
      sample: #"""
      {"schema_version":1,"operation":"upsert","status":"created","use_case_id":\#
      "synthetic.case","file_path":"use-cases/synthetic.yml","before_hash":null,\#
      "after_hash":\#
      "sha256:1111111111111111111111111111111111111111111111111111111111111111",\#
      "diagnostics":[]}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  /// The evidence envelopes and the plan they are summarised into.
  private static func validateEvidenceContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    check(
      "evidence-append-result.schema.json",
      sample: #"""
      {"schema_version":1,"appended":true,"event":\#
      \#(SyntheticContractSamples.evidenceEventSample),\#
      "ledger_path":"evidence/by-id/ev/evidence.synthetic.jsonl",\#
      "durability":"file_synced"}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    check(
      "evidence-status-result.schema.json",
      sample: #"""
      {"schema_version":1,"complete":true,"integrity":{"state":"clean",\#
      "unknown_scope_damage":false,"invalid_aggregate_count":0,"torn_tail_count":0},\#
      "ledgers":[],"aggregates":[],"counts":{"ledgers":0,"events_loaded":0,\#
      "aggregates_total":0,"aggregates_active":0,"aggregates_invalid":0}}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    check(
      "presentation-plan-result.schema.json",
      sample: #"""
      {"schema_version":1,"outcome":"generated","plan":\#
      \#(SyntheticContractSamples.presentationPlanSample),\#
      "candidate_summary":{"considered":0,"eligible":0,"selected":0,"excluded":0,\#
      "excluded_by_reason":{}},"input_integrity":{"matrix":"clean","evidence":"clean"}}
      """#,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  /// The showcase run envelopes, which all carry the same event and status.
  private static func validateShowcaseContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    check(
      "showcase-run-status-result.schema.json",
      sample: SyntheticContractSamples.showcaseStatusSample,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )

    for fileName in [
      "showcase-start-result.schema.json",
      "showcase-event-append-result.schema.json",
      "showcase-finish-result.schema.json",
      "showcase-approval-result.schema.json",
    ] {
      check(
        fileName,
        sample: #"""
        {"schema_version":1,"run_id":"run.synthetic","appended_event_ids":\#
        ["evt_showcase_synthetic_1"],\#
        "event":\#(SyntheticContractSamples.showcaseEventSample),\#
        "status":\#(SyntheticContractSamples.showcaseStatusSample)}
        """#,
        registry: registry,
        validatedIdentifiers: &validatedIdentifiers,
        diagnostics: &diagnostics,
      )
    }
  }

  /// The Phase 1 gap schemas: markers, the release gate, and the trust engine.
  private static func validateTrustContracts(
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    for (fileName, sample) in SyntheticContractSamples.newSchemaSamples {
      check(
        fileName,
        sample: sample,
        registry: registry,
        validatedIdentifiers: &validatedIdentifiers,
        diagnostics: &diagnostics,
      )
    }

    let toolEnvelope = CliResult.make(
      command: "matrix.status",
      data: .object(JSONObject([("use_cases", .array([]))])),
    ).jsonValue()
    check(
      "mcp-tool-results.schema.json",
      value: toolEnvelope,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  // MARK: - Running one sample

  private static func check(
    _ fileName: String,
    sample: String,
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    // A sample that does not parse becomes null, which no schema accepts: the
    // failure surfaces as diagnostics rather than being swallowed.
    check(
      fileName,
      value: (try? JSONParser.parse(sample)) ?? .null,
      registry: registry,
      validatedIdentifiers: &validatedIdentifiers,
      diagnostics: &diagnostics,
    )
  }

  private static func check(
    _ fileName: String,
    value: JSONValue,
    registry: SchemaRegistry,
    validatedIdentifiers: inout Set<String>,
    diagnostics: inout [Diagnostic],
  ) {
    let identifier = SchemaRegistry.schemaIdentifier(forFileName: fileName)
    let result = registry.validate(schemaIdentifier: identifier, value: value, sourcePath: nil)
    validatedIdentifiers.insert(identifier)
    diagnostics.append(contentsOf: result.diagnostics)
  }
}
