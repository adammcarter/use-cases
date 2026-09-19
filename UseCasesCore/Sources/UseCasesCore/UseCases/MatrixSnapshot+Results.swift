/// The two wire results a snapshot is reported through, in the frozen key order
/// of `matrix-validation-result.schema.json` and `matrix-list-result.schema.json`
/// (ADR 0007 decision 8). Built as ``JSONValue`` so ``JSONWriter`` keeps the
/// order; `JSONEncoder` would not.
extension MatrixSnapshot {
  /// `toMatrixValidationResult(snapshot)`.
  public func validationResult() -> JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("valid", .bool(isComplete)),
      ("integrity", integrityJSON),
      ("files", .array(files.map(Self.fileJSON))),
      ("counts", countsJSON),
      ("ambiguous_ids", .array(ambiguousUseCaseIdentifiers.map { group in
        .object(JSONObject([
          ("entity_kind", .string("use_case")),
          ("id", .string(group.identifier)),
          ("source_paths", .array(group.sourcePaths.map(JSONValue.string))),
        ]))
      })),
    ]))
  }

  /// `toMatrixListResult(snapshot, useCases)`.
  public func listResult(for useCases: [LoadedUseCase]) -> JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("integrity", integrityJSON),
      ("use_cases", .array(useCases.map(Self.listEntryJSON))),
      ("counts", .object(JSONObject([
        ("returned", .number(Double(useCases.count))),
        ("total_addressable", .number(Double(addressableUseCases.count))),
      ]))),
    ]))
  }

  private var integrityJSON: JSONValue {
    .object(JSONObject([
      ("state", .string(integrity.state.rawValue)),
      ("populated", .bool(integrity.isPopulated)),
      ("blocking_diagnostic_count", .number(Double(integrity.blockingDiagnosticCount))),
    ]))
  }

  private var countsJSON: JSONValue {
    .object(JSONObject([
      ("files_discovered", .number(Double(counts.filesDiscovered))),
      ("files_loaded", .number(Double(counts.filesLoaded))),
      ("files_excluded", .number(Double(counts.filesExcluded))),
      ("use_case_candidates", .number(Double(counts.useCaseCandidates))),
      ("use_cases_addressable", .number(Double(counts.useCasesAddressable))),
      ("use_cases_ambiguous", .number(Double(counts.useCasesAmbiguous))),
      ("use_cases_structurally_clean", .number(Double(counts.useCasesStructurallyClean))),
      ("broken_references", .number(Double(counts.brokenReferences))),
    ]))
  }

  /// A hash is written only when it is present AND non-empty, as the
  /// TypeScript's `...(file.semantic_hash ? { … } : {})` spreads it.
  private static func fileJSON(_ file: MatrixFileResult) -> JSONValue {
    var object = JSONObject([
      ("path", .string(file.path)),
      ("status", .string(file.status.rawValue)),
    ])
    if let semanticHash = file.semanticHash, !semanticHash.isEmpty {
      object["semantic_hash"] = .string(semanticHash)
    }
    if let fileHash = file.fileHash, !fileHash.isEmpty {
      object["file_hash"] = .string(fileHash)
    }
    return .object(object)
  }

  /// A row's list entry. A member the row lacks is left out, as
  /// `JSON.stringify` leaves out `undefined`; the schema requires every one of
  /// them, so a loaded row has them all.
  private static func listEntryJSON(_ item: LoadedUseCase) -> JSONValue {
    var object = JSONObject()
    object["id"] = item.value["id"]
    object["title"] = item.value["title"]
    object["feature_id"] = item.feature["id"]
    object["lifecycle"] = item.value["lifecycle"]
    object["value_tier"] = item.value["value_tier"]
    object["journey_role"] = item.value["journey_role"]
    object["source_path"] = .string(item.source.path)
    object["semantic_hash"] = .string(item.semanticHash)
    let hosts = (item.value["host_applicability"]?.arrayValue ?? [])
      .filter { host in
        host["supported"] == .bool(true)
      }
      .compactMap { host in
        host["host_surface"]
      }
    object["host_surfaces"] = .array(hosts)
    object["tags"] = item.value["tags"] ?? .array([])
    return .object(object)
  }
}
