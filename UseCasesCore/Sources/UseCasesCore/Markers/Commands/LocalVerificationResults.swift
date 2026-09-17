/// The keyless tier's inputs `scan` reads: the unsigned verification-results
/// ledger and the performed runs distilled from the observation ledger.
public enum LocalVerificationResults {
  /// `DEFAULT_VERIFICATION_RESULTS_FILENAME`: what `verify --out` writes under
  /// the data root's `.use-cases` directory, and where `scan` looks for it.
  public static let defaultFilename = "verification-results.jsonl"

  /// `loadLocalVerificationResults`: one result per line holding an object
  /// whose `row_id`, `verification_context_hash`, `binding_set_hash` and
  /// `status` are all strings. A blank, malformed or incomplete line is
  /// skipped, never raised. `attested` is true only for a record carrying the
  /// attestation `runKey` produces; a nil key attests nothing.
  ///
  /// A record holding a number JSON cannot spell (`1e999`) cannot be
  /// canonicalised for its attestation check, and is raised as the TypeScript
  /// raises it.
  public static func parse(
    _ text: String,
    runKey: String?,
  ) throws(CodeUnitCanonicalJSONError) -> [LocalVerificationResult] {
    var results: [LocalVerificationResult] = []
    for raw in JavaScriptString.split(text, on: CodeUnits.lineFeed) {
      let line = JavaScriptString.trim(raw)
      guard !line.isEmpty else {
        continue
      }
      let parsed: JSONValue
      do throws(SchemaError) {
        parsed = try JSONParser.parse(line)
      } catch {
        continue
      }
      guard let record = parsed.objectValue,
            let rowIdentifier = record["row_id"]?.stringValue,
            let contextHash = record["verification_context_hash"]?.stringValue,
            let bindingSetHash = record["binding_set_hash"]?.stringValue,
            let status = record["status"]?.stringValue
      else {
        continue
      }
      try results.append(LocalVerificationResult(
        rowIdentifier: rowIdentifier,
        contextHash: contextHash,
        bindingSetHash: bindingSetHash,
        passed: status == "pass",
        attested: RunAttestation.verify(record: record, key: runKey),
      ))
    }
    return results
  }

  /// The bridge from the evidence ledger's performed runs to the freshness
  /// input's: one run per row, the row id exact. Freshness reads only the row,
  /// so a ledger argv holding anything but strings keeps its run and carries
  /// no argv.
  public static func freshnessPerformedRuns(_ runs: [EvidencePerformedRun]) -> [PerformedRun] {
    runs.map { run in
      let strings = run.argv.compactMap(\.stringValue)
      return PerformedRun(
        rowIdentifier: run.rowIdentifier,
        argv: strings.count == run.argv.count ? strings : nil,
      )
    }
  }

  /// The runs `scan` counts when the caller injects none: the observation
  /// ledger replayed for this workspace, keeping only tool-executed passing
  /// runs against each row's CURRENT semantic hash. A ledger that cannot be
  /// replayed yields none, never an error.
  static func performedRuns(
    context: ResolvedWorkspaceContext,
    loaded: LoadedMarkerRows,
  ) -> [PerformedRun] {
    let hashes = loaded.snapshot.addressableUseCases.map { useCase in
      (useCase.value["id"]?.stringValue ?? "", useCase.semanticHash)
    }
    do throws(EvidenceEventError) {
      let snapshot = try EvidenceReplay.replay(context: context)
      return freshnessPerformedRuns(PerformedRuns.collect(
        snapshot: snapshot,
        currentSemanticHashes: hashes,
      ))
    } catch {
      return []
    }
  }
}
