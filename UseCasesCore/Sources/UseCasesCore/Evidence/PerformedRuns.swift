/// A row backed by a run the tool itself executed (`PerformedRun` in
/// performedRuns.ts). Not ``PerformedRun``: that is the freshness input, whose
/// `argv` is strings only, while a ledger's argv is whatever JSON it holds.
public struct EvidencePerformedRun: Sendable, Equatable {
  public let rowIdentifier: String
  /// The argv the tool spawned, as the ledger holds it.
  public let argv: [JSONValue]

  /// `{ row_id, argv }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([("row_id", .string(rowIdentifier)), ("argv", .array(argv))]))
  }
}

/// packages/core/src/evidence/performedRuns.ts: the evidence tier the
/// acceptance claim may honestly count.
public enum PerformedRuns {
  /// `collectPerformedRuns`: every row backed by at least one current,
  /// tool-executed, passing run — one entry per row, the first run found, in
  /// row-id code-unit order.
  ///
  /// `currentSemanticHashes` is the TypeScript's `Map` built from entries: a
  /// later entry for a row replaces an earlier one, and row ids match by exact
  /// code units.
  public static func collect(
    snapshot: EvidenceSnapshot,
    currentSemanticHashes: some Sequence<(String, String)>,
  ) -> [EvidencePerformedRun] {
    var hashes = OrderedStringMap<String>()
    for (row, hash) in currentSemanticHashes {
      hashes[row] = hash
    }
    var byRow = OrderedStringMap<EvidencePerformedRun>()
    for aggregate in snapshot.aggregates {
      for run in runs(of: aggregate, currentSemanticHashes: hashes)
        where byRow[run.rowIdentifier] == nil
      {
        byRow[run.rowIdentifier] = run
      }
    }
    return byRow.pairs.map(\.value).sorted { left, right in
      JavaScriptString.precedes(left.rowIdentifier, right.rowIdentifier)
    }
  }

  /// `performedRunsOf`: each clause is a way the record could be a claim
  /// rather than a run.
  private static func runs(
    of aggregate: EvidenceAggregateState,
    currentSemanticHashes: OrderedStringMap<String>,
  ) -> [EvidencePerformedRun] {
    guard aggregate.status == .active,
          let observation = aggregate.effectiveObservation,
          JavaScriptValue.strictlyEquals(aggregate.assurance["class"], "reproducible")
    else {
      return []
    }
    let method = observation["method"]
    guard JavaScriptValue.strictlyEquals(
      JavaScriptValue.member(method, "type"),
      "structured_command",
    ),
      let argv = JavaScriptValue.member(method, "argv")?.arrayValue, !argv.isEmpty
    else {
      return []
    }
    let verdict = JavaScriptValue.coalesce(observation["verdict"], .string("pass"))
    guard JavaScriptValue.strictlyEquals(observation["result"], "pass"),
          JavaScriptValue.strictlyEquals(verdict, "pass")
    else {
      return []
    }
    var runs: [EvidencePerformedRun] = []
    for target in observation["targets"]?.arrayValue ?? [] {
      guard let row = JavaScriptValue.member(target, "use_case_id")?.stringValue,
            let currentHash = currentSemanticHashes[row],
            JavaScriptValue.strictlyEquals(
              JavaScriptValue.member(target, "use_case_semantic_hash"),
              currentHash,
            )
      else {
        continue
      }
      runs.append(EvidencePerformedRun(rowIdentifier: row, argv: argv))
    }
    return runs
  }
}
