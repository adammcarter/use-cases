// F3 — recompute the run-binding an approval token must match, PURELY from the
// live run's ledger. Called in two places that MUST agree byte-for-byte:
//   1) when minting a request (so the human signs the real run's facts), and
//   2) inside appendShowcaseApproval (so the token is re-checked against the
//      live run, not against whatever the caller claims).
//
// Because it is a pure function of the ledger + plan, an agent cannot slip a
// different value past the check: the plugin recomputes it independently.
import { sha256 } from "../markers/canonicalJson.js";
import { canonicalJson } from "../markers/canonicalJson.js";
import { readShowcaseEvents } from "./jsonlLedger.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { ShowcaseEvent } from "./types.js";
import type { ApprovalRequestBinding } from "./approvalToken.js";
import { UseCasesPluginError } from "../errors.js";

// Compute the binding from an already-read, ordered event list.
export function computeApprovalBindingFromEvents(
  runId: string,
  events: ShowcaseEvent[]
): ApprovalRequestBinding {
  const ordered = events.slice().sort((left, right) => left.sequence - right.sequence);
  const start = ordered.find((event) => event.event_type === "run_started");
  const finish = ordered.slice().reverse().find((event) => event.event_type === "run_finished");
  if (!finish) {
    throw new UseCasesPluginError(
      "Approval binding requires a finished showcase run.",
      "showcase.finish_required_for_approval"
    );
  }
  const planContentHash = String((start?.payload as { plan_content_hash?: string } | undefined)?.plan_content_hash ?? "");
  const gitCommit = String((start?.payload as { git_commit?: string } | undefined)?.git_commit ?? "unknown");

  // Ledger head: a hash over the full ordered event-id chain. Any appended or
  // reordered event changes it, so a token minted against one ledger state does
  // not bind to a later one.
  const ledgerHeadHash = sha256(canonicalJson({ run_id: runId, event_ids: ordered.map((event) => event.event_id) }));

  // Evidence digest: a hash over the observation + verdict evidence.
  const evidenceIds = ordered
    .filter((event) => event.event_type === "observation_recorded" || event.event_type === "verdict_recorded")
    .map((event) => event.event_id)
    .sort();
  const evidenceDigest = sha256(canonicalJson({ run_id: runId, evidence_event_ids: evidenceIds }));

  // CI freshness digest: from a run_started freshness snapshot when present,
  // else derived deterministically from the plan hash + finish event.
  const freshness = (start?.payload as { ci_freshness_digest?: string } | undefined)?.ci_freshness_digest;
  const ciFreshnessDigest =
    typeof freshness === "string" && freshness.length > 0
      ? freshness
      : sha256(canonicalJson({ plan_content_hash: planContentHash, finish_event_id: finish.event_id }));

  return {
    run_id: runId,
    finish_event_id: finish.event_id,
    plan_content_hash: planContentHash,
    ledger_head_hash: ledgerHeadHash,
    evidence_digest: evidenceDigest,
    git_commit: gitCommit,
    ci_freshness_digest: ciFreshnessDigest
  };
}

// Read the live run and compute its approval binding.
export function computeRunApprovalBinding(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
}): ApprovalRequestBinding {
  const read = readShowcaseEvents(options.context, options.runId);
  return computeApprovalBindingFromEvents(options.runId, read.events);
}
