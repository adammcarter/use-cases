/// Everything `deriveFreshness` indexes before it walks the rows: the
/// reconciliation, the scan and the evidence grouped by row, the global
/// integrity errors with their remediation, and the likely renames.
///
/// Every map is keyed by code unit (``OrderedStringMap``): a row id can be a
/// malformed marker's slug, which no schema constrains.
struct FreshnessIndex {
  let reconciliation: ReconciliationResult
  private(set) var reconciliationByRow = OrderedStringMap<RowReconciliation>()
  private(set) var bindingsByRow = OrderedStringMap<[CurrentBindingRecord]>()
  private(set) var scanErrorsByRow = OrderedStringMap<[MarkerError]>()
  private(set) var globalIntegrity: [JSONObject] = []
  private(set) var unregisteredByRow = OrderedStringMap<[UnregisteredDetection]>()
  private(set) var renamedFrom = OrderedStringMap<String>()
  private(set) var evidenceByRow = OrderedStringMap<[FreshnessProofEvent]>()
  private(set) var localResultsByRow = OrderedStringMap<[LocalVerificationResult]>()
  private(set) var performedRunRows = OrderedStringSet()
  private(set) var contextHashes: OrderedStringMap<String>?
  private(set) var rowById = OrderedStringMap<FreshnessInputRow>()
  private(set) var rowIdentifiers: [String] = []

  init(_ input: FreshnessInput) {
    reconciliation = RegistryReconciliation.reconcile(registry: input.registry, scan: input.scan)
    for recon in reconciliation.rows {
      reconciliationByRow[recon.rowIdentifier] = recon
    }
    for binding in input.scan.bindings {
      bindingsByRow[binding.rowIdentifier, default: []].append(binding)
    }
    indexIntegrity(input)
    indexRenames()
    indexEvidence(input)
    indexRows(input)
  }

  private mutating func indexIntegrity(_ input: FreshnessInput) {
    globalIntegrity = (input.globalIntegrityErrors ?? []).map { raw in
      var error = JSONObject([("code", .string("LEDGER_INTEGRITY_ERROR"))])
      for (key, value) in raw.pairs {
        error[key] = value
      }
      return error
    }
    for error in input.scan.errors {
      guard let slug = error.slug else {
        globalIntegrity.append(JSONObject([
          ("code", .string(error.code.rawValue)),
          ("file_path", .string(error.filePath)),
          ("line", .number(Double(error.line))),
          ("message", .string(error.message)),
        ]))
        continue
      }
      let rowIdentifier = MarkerSlug.split(slug)?.rowIdentifier ?? slug
      scanErrorsByRow[rowIdentifier, default: []].append(error)
    }
    for detection in reconciliation.unregistered {
      unregisteredByRow[detection.rowIdentifier, default: []].append(detection)
    }
  }

  /// A rename leaves two halves: the lost row — still in the matrix with its
  /// marker gone, or gone from the matrix so its registration is a
  /// REGISTRY_ROW_MISSING error — and an unregistered marker with a near id.
  private mutating func indexRenames() {
    let orphanedRows = globalIntegrity
      .filter { error in
        JavaScriptValue.strictlyEquals(error["code"], "REGISTRY_ROW_MISSING")
          && JavaScriptValue.isTruthy(error["row_id"])
      }
      .compactMap { error in
        error["row_id"]
      }
    renamedFrom = FreshnessRenames.infer(
      unregistered: reconciliation.unregistered,
      candidates: reconciliation.missing.map { missing in
        .string(missing.rowIdentifier)
      } + orphanedRows,
    )
    let renamedTo = FreshnessRenames.renamedTo(
      renamedFrom,
      unregistered: reconciliation.unregistered,
    )
    FreshnessRenames.remediate(&globalIntegrity, renamedTo: renamedTo)
  }

  private mutating func indexEvidence(_ input: FreshnessInput) {
    for event in input.evidence {
      evidenceByRow[event.rowIdentifier, default: []].append(event)
    }
    for (rowIdentifier, events) in evidenceByRow.pairs {
      evidenceByRow[rowIdentifier] = Self.newestFirst(events)
    }
    for run in input.performedRuns ?? [] {
      performedRunRows.insert(run.rowIdentifier)
    }
    for result in input.localResults ?? [] {
      localResultsByRow[result.rowIdentifier, default: []].append(result)
    }
    contextHashes = input.currentContextHashes.map { entries in
      var map = OrderedStringMap<String>()
      for entry in entries {
        map[entry.rowIdentifier] = entry.contextHash
      }
      return map
    }
  }

  /// The union of the loaded rows, the reconciled rows and the rows scan
  /// errors name — so nothing silently vanishes — in code-unit order.
  private mutating func indexRows(_ input: FreshnessInput) {
    var identifiers = OrderedStringSet()
    for row in input.rows {
      rowById[row.rowIdentifier] = row
      identifiers.insert(row.rowIdentifier)
    }
    for recon in reconciliation.rows {
      identifiers.insert(recon.rowIdentifier)
    }
    for rowIdentifier in scanErrorsByRow.keys {
      identifiers.insert(rowIdentifier)
    }
    rowIdentifiers = identifiers.sortedMembers
  }

  /// Newest first by `created_at` in code-unit order; equal timestamps keep
  /// their ledger order.
  static func newestFirst(_ events: [FreshnessProofEvent]) -> [FreshnessProofEvent] {
    events.enumerated()
      .sorted { left, right in
        if JavaScriptString.precedes(right.element.createdAt, left.element.createdAt) {
          return true
        }
        if JavaScriptString.precedes(left.element.createdAt, right.element.createdAt) {
          return false
        }
        return left.offset < right.offset
      }
      .map(\.element)
  }
}

extension OrderedStringMap {
  subscript(
    key: String,
    default defaultValue: @autoclosure () -> Value,
  ) -> Value {
    get {
      self[key] ?? defaultValue()
    }
    set {
      self[key] = newValue
    }
  }
}
