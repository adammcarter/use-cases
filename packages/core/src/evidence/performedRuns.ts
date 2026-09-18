// Performed runs: the evidence tier the acceptance claim may honestly count.
//
// The observation ledger (`evidence/by-id/**`) records everything anyone
// observed about a behaviour, and it deliberately carries NO trust authority —
// an agent can write "I tried it, it worked" and the ledger grades that the
// weakest tier. The acceptance claim used to ignore the whole ledger for exactly
// that reason, which left it reading the one file a text editor could forge and
// nothing else.
//
// The distinction it was missing is already in the data: `assurance.class` says
// whether the record is a report or a REPRODUCIBLE run, and a tool-executed
// record names the argv it spawned. `collectPerformedRuns` selects on that, so
// the claim counts runs the tool performed and still ignores prose.
//
// This is where the journey/unit distinction actually lands. `verify` spawns a
// row's verifier — usually a test filter, which the repo's own runner header
// concedes is "WEAKER evidence than a journey". A performed run is a command
// driven against the shipped product and recorded with the argv that drove it.
// Both count as proven; they are counted SEPARATELY so a claim can never present
// a wall of unit tests as a wall of demonstrations.
import type { EvidenceAggregateState, EvidenceSnapshot } from "./types.js";

export interface PerformedRun {
  row_id: string;
  // The argv the tool actually spawned. Carried so a reader can check the claim
  // rather than take it: a performed run that cannot say what it ran is not one.
  argv: string[];
}

// Does this aggregate record a run the TOOL executed, still current against the
// row it targets? Every clause is a way the record could be a claim rather than
// a run, and each is checked rather than assumed.
function performedRunsOf(
  aggregate: EvidenceAggregateState,
  currentSemanticHashes: ReadonlyMap<string, string>
): PerformedRun[] {
  // Voided, superseded, invalidated or malformed: history, not a live claim.
  if (aggregate.status !== "active") {
    return [];
  }
  const observation = aggregate.effectiveObservation;
  if (!observation) {
    return [];
  }
  // `reproducible` is the ledger's own top class: capture_method "executed" via
  // a command or test. Anything below it is a report, and reports do not prove.
  if ((aggregate.assurance as { class?: string }).class !== "reproducible") {
    return [];
  }
  // The tell that separates a run from a claim to have run: only a process that
  // spawned something knows the argv it spawned. Nothing but the tool writes it.
  const method = observation.method;
  if (method.type !== "structured_command" || !Array.isArray(method.argv) || method.argv.length === 0) {
    return [];
  }
  // A run that failed is evidence the behaviour does NOT hold.
  if (observation.result !== "pass" || (observation.verdict ?? "pass") !== "pass") {
    return [];
  }
  // Staleness, this tier's version of it: the run proved the row AS IT WAS. Edit
  // the row and the semantic hash moves, and the old run stops answering for it.
  // Without this the performed-run tier would be the only one that never decays.
  const runs: PerformedRun[] = [];
  for (const target of observation.targets) {
    const currentHash = currentSemanticHashes.get(target.use_case_id);
    if (currentHash === undefined || currentHash !== target.use_case_semantic_hash) {
      continue;
    }
    runs.push({ row_id: target.use_case_id, argv: [...method.argv] });
  }
  return runs;
}

// Every row backed by at least one current, tool-executed, passing run. One
// entry per row (a row driven three times is still one proven row), in stable
// row-id order.
export function collectPerformedRuns(
  snapshot: EvidenceSnapshot,
  currentSemanticHashes: ReadonlyMap<string, string>
): PerformedRun[] {
  const byRow = new Map<string, PerformedRun>();
  for (const aggregate of snapshot.aggregates) {
    for (const run of performedRunsOf(aggregate, currentSemanticHashes)) {
      if (!byRow.has(run.row_id)) {
        byRow.set(run.row_id, run);
      }
    }
  }
  return [...byRow.values()].sort((left, right) =>
    left.row_id < right.row_id ? -1 : left.row_id > right.row_id ? 1 : 0
  );
}
